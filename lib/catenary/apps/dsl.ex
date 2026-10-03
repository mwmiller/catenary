defmodule Catenary.Apps.DSL do
  @moduledoc """
  The DSL compiler: source text to the WAT that watusi compiles.

  The pipeline is tokenize → parse → check → emit. Every failure carries a
  source position: `compile/1` renders it as `{:error, "line L, col C:
  message"}` and `diagnostic/1` returns it structured, the way the editor's
  lint gutter wants it. Neither raises on user input.

  The language is deliberately fixed (decision #16): numbered handlers,
  flat per-handler scope, no loops, no closures. The compiler owns all ABI
  ceremony — dispatch, the effect list, the constant pool, the handle
  prologue — and a well-typed program can only emit well-formed effects.
  """

  alias Catenary.Apps.DSL.Runtime

  @type compile_error :: {:error, String.t()}

  # Host operations and the arguments the host will accept: `req` must be
  # present, `opt` may be. Checked against Catenary.AppHost.dispatch/3.
  @host_ops %{
    "log_read" => %{req: ~w(log_id seq), opt: ~w(author)},
    "log_head" => %{req: ~w(log_id), opt: ~w(author)},
    "log_range" => %{req: ~w(log_id), opt: ~w(author from count)},
    "refs" => %{req: ~w(log_id seq), opt: ~w(author)},
    "entry_meta" => %{req: ~w(log_id seq), opt: ~w(author)},
    "timeline" => %{req: [], opt: ~w(author kind cursor limit)},
    "profile" => %{req: [], opt: ~w(author)},
    "storage_get" => %{req: ~w(key), opt: []},
    "storage_set" => %{req: ~w(key value), opt: []}
  }

  # Draw ops and their wire fields. `req` must be given, `opt` may be;
  # the colour defaults to @default_color when left out.
  @draw_ops %{
    "fill_rect" => %{req: ~w(x y w h), opt: ~w(c)},
    "stroke_rect" => %{req: ~w(x y w h lw), opt: ~w(c)},
    "line" => %{req: ~w(x1 y1 x2 y2 lw), opt: ~w(c)},
    "stroke_path" => %{req: ~w(pts lw), opt: ~w(c)},
    "fill_path" => %{req: ~w(pts), opt: ~w(c)},
    "text" => %{req: ~w(s x y), opt: ~w(size c)},
    "translate" => %{req: ~w(x y), opt: []},
    "scale" => %{req: ~w(x y), opt: []}
  }

  @view_builds ~w(text col row canvas)
  @view_arity %{"text" => 1, "canvas" => 2}
  @builtin_arity %{"show" => 1, "len" => 1, "floor" => 1, "min" => 2, "max" => 2}
  @default_color "#64748b"

  # Words a program may not take as its own: syntax, builtins, draw ops.
  @reserved ~w(on init data err tick ui let if else match when want
                print render draw animate true false null and or
                text col row canvas show len floor min max
                fill_rect stroke_rect line stroke_path fill_path
                translate scale)

  # Field names the ABI and the effect wire need, interned before any of
  # the program's own strings so the pool is order-deterministic.
  @abi_strings ~w(msg init data tick ui err t event ref ok error do text
                  view ops on op args s kids w h
                  print render animate want draw col row canvas
                  x y lw c x1 y1 x2 y2 pts size
                  log_id seq author from count kind cursor limit key value) ++
                 [@default_color]

  # Operator spellings to their AST atoms. Explicit, because relying on
  # String.to_existing_atom for punctuation or rarely-used words is a
  # coin flip at runtime.
  @bin_ops %{
    "==" => :eq,
    "!=" => :ne,
    "<" => :lt,
    "<=" => :le,
    ">" => :gt,
    ">=" => :ge,
    "+" => :add,
    "-" => :sub,
    "*" => :mul,
    "/" => :div,
    "%" => :rem
  }

  @spec compile(String.t()) :: {:ok, String.t()} | compile_error
  def compile(source) when is_binary(source) do
    source |> pipeline() |> format_error()
  end

  # The diagnostic the editor renders inline: nil when the buffer compiles,
  # otherwise the position and message `compile/1` would print. Positions are
  # 1-based line and column, the same coordinates the error strings carry.
  @spec diagnostic(String.t()) ::
          %{line: pos_integer(), col: pos_integer(), message: String.t()} | nil
  def diagnostic(source) when is_binary(source) do
    case pipeline(source) do
      {:ok, _wat} -> nil
      {:error, {line, col, message}} -> %{line: line, col: col, message: message}
    end
  end

  defp pipeline(source) do
    with {:ok, tokens} <- tokenize(source),
         {:ok, lines} <- to_lines(tokens),
         {:ok, handlers} <- parse_program(lines),
         {:ok, plan} <- check(handlers) do
      {:ok, emit(plan)}
    end
  end

  defp format_error({:ok, wat}), do: {:ok, wat}
  defp format_error({:error, {line, col, msg}}), do: {:error, "line #{line}, col #{col}: #{msg}"}

  defp err(line, col, msg), do: {:error, {line, col, msg}}

  # ================================================================ lexing

  @sym ~w|== != <= >= = < > + - * / % ( ) [ ] { } : , .|

  defp tokenize(src), do: do_tokenize(src, 1, 1, [])

  defp do_tokenize(<<>>, _line, _col, acc), do: {:ok, Enum.reverse(acc)}

  defp do_tokenize(<<"#", rest::binary>>, line, col, acc),
    do: do_tokenize(skip_comment(rest), line, col, acc)

  defp do_tokenize(<<"\n", rest::binary>>, line, _col, acc),
    do: do_tokenize(rest, line + 1, 1, [{:nl, "\n", line, 1} | acc])

  defp do_tokenize(<<" ", rest::binary>>, line, col, acc),
    do: do_tokenize(rest, line, col + 1, acc)

  defp do_tokenize(<<"\t", _::binary>>, line, col, _acc),
    do: err(line, col, "tabs are not allowed; use spaces")

  defp do_tokenize(<<"\"", rest::binary>>, line, col, acc) do
    case lex_string(rest, line, col + 1, []) do
      {:ok, value, rest, end_col} ->
        do_tokenize(rest, line, end_col, [{:str, value, line, col} | acc])

      {:error, _} = error ->
        error
    end
  end

  defp do_tokenize(<<c, _::binary>> = src, line, col, acc) when c in ?0..?9 do
    {raw, rest, _} = take_while(src, col, &(&1 in ?0..?9 or &1 in [?., ?e, ?E, ?+, ?-]))

    case refine_number(raw) do
      {text, extra} ->
        case Float.parse(text) do
          {num, ""} ->
            do_tokenize(
              extra <> rest,
              line,
              col + byte_size(text),
              [{:num, num, line, col} | acc]
            )

          _ ->
            err(line, col, "bad number #{inspect(text)}")
        end
    end
  end

  defp do_tokenize(<<c, _::binary>> = src, line, col, acc)
       when c in ?a..?z or c in ?A..?Z or c == ?_ do
    {text, rest, end_col} =
      take_while(src, col, &(&1 in ?a..?z or &1 in ?A..?Z or &1 in ?0..?9 or &1 == ?_))

    do_tokenize(rest, line, end_col, [{:ident, text, line, col} | acc])
  end

  defp do_tokenize(src, line, col, acc) do
    case Enum.find(@sym, &String.starts_with?(src, &1)) do
      nil ->
        {c, _rest, _} = take_char(src, col)
        err(line, col, "unexpected character #{inspect(c)}")

      sym ->
        rest = binary_part(src, byte_size(sym), byte_size(src) - byte_size(sym))
        do_tokenize(rest, line, col + byte_size(sym), [{:sym, sym, line, col} | acc])
    end
  end

  # The raw scan may swallow `1-2` or `1..2`; trim back to the longest
  # valid number prefix so `-` and `.` re-enter the token stream.
  defp refine_number(text) do
    case Regex.run(~r/^\d+(?:\.\d+)?(?:[eE][+-]?\d+)?/, text) do
      [good] ->
        {good, binary_part(text, byte_size(good), byte_size(text) - byte_size(good))}

      nil ->
        {text, ""}
    end
  end

  defp take_while(src, col, pred), do: take_while(src, col, pred, [])

  defp take_while(<<c, rest::binary>> = src, col, pred, acc) do
    if pred.(c) do
      take_while(rest, col + 1, pred, [c | acc])
    else
      {acc |> Enum.reverse() |> List.to_string(), src, col}
    end
  end

  defp take_while(<<>>, col, _pred, acc),
    do: {acc |> Enum.reverse() |> List.to_string(), "", col}

  defp take_char(<<c::utf8, rest::binary>>, col), do: {<<c::utf8>>, rest, col + 1}

  defp skip_comment(<<"\n", _::binary>> = rest), do: rest
  defp skip_comment(<<_::utf8, rest::binary>>), do: skip_comment(rest)
  defp skip_comment(<<>>), do: <<>>

  defp lex_string(<<>>, line, _col, _acc), do: err(line, 1, "unterminated string")

  defp lex_string(<<"\"", rest::binary>>, _line, col, acc),
    do: {:ok, acc |> Enum.reverse() |> List.to_string(), rest, col + 1}

  defp lex_string(<<"\\", c, rest::binary>>, line, col, acc) do
    case c do
      ?n -> lex_string(rest, line, col + 2, [?\n | acc])
      ?t -> lex_string(rest, line, col + 2, [?\t | acc])
      ?r -> lex_string(rest, line, col + 2, [?\r | acc])
      ?" -> lex_string(rest, line, col + 2, [?" | acc])
      ?\\ -> lex_string(rest, line, col + 2, [?\\ | acc])
      _ -> err(line, col, "unknown escape \\#{<<c>>}")
    end
  end

  defp lex_string(<<"\n", _::binary>>, line, _col, _acc),
    do: err(line, 1, "unterminated string")

  defp lex_string(<<c::utf8, rest::binary>>, line, col, acc),
    do: lex_string(rest, line, col + 1, [c | acc])

  # ============================================================ line split

  # Tokens become logical lines. Whitespace is already gone, so a line's
  # indent is the column of its first token minus one. Blank and
  # comment-only lines produced no tokens at all.
  defp to_lines(tokens), do: split_lines(tokens, [], [])

  defp split_lines([], [], acc), do: {:ok, Enum.reverse(acc)}
  defp split_lines([], cur, acc), do: {:ok, Enum.reverse([finish_line(cur) | acc])}
  defp split_lines([{:nl, _, _, _} | rest], [], acc), do: split_lines(rest, [], acc)

  defp split_lines([{:nl, _, _, _} | rest], cur, acc),
    do: split_lines(rest, [], [finish_line(cur) | acc])

  defp split_lines([token | rest], cur, acc), do: split_lines(rest, [token | cur], acc)

  defp finish_line(rev_cur) do
    tokens = Enum.reverse(rev_cur)
    {_kind, _value, line, col} = hd(tokens)
    {col - 1, line, tokens}
  end

  # ================================================================ parsing

  defp parse_program(lines), do: parse_handlers(lines, [])

  defp parse_handlers([], acc), do: {:ok, Enum.reverse(acc)}

  defp parse_handlers([{0, _line, tokens} | rest], acc) do
    with {:ok, handler, rest} <- parse_on(tokens, rest) do
      parse_handlers(rest, [handler | acc])
    end
  end

  defp parse_handlers([{indent, line, _tokens} | _], _acc),
    do: err(line, indent + 1, "unexpected indent (handlers start at the top level)")

  defp parse_on([{:ident, "on", _, _} | tokens], rest) do
    with {:ok, kind, params, tokens} <- on_kind(tokens),
         {:ok, _colon, tokens} <- expect_sym(tokens, ":"),
         {:ok, []} <- expect_end(tokens),
         {:ok, block, after_block} <- child_block(rest, 0),
         {:ok, body, []} <- parse_block(block, hd_block_indent(block)) do
      {:ok, {:on, kind, params, body}, after_block}
    end
  end

  defp parse_on([{_, _, line, col} | _], _),
    do:
      err(
        line,
        col,
        "expected a handler: on init: / on data(\"label\", name): / on tick(name): / on ui(name): / on err(name):"
      )

  defp parse_on([], _), do: err(1, 1, "on init: is required")

  defp hd_block_indent([{indent, _, _} | _]), do: indent
  defp hd_block_indent([]), do: 0

  defp on_kind([{:ident, "init", _, _} | rest]), do: {:ok, :init, [], rest}

  defp on_kind([
         {:ident, "data", _, _},
         {:sym, "(", _, _},
         {:str, label, line, col},
         {:sym, ",", _, _},
         {:ident, name, _, _},
         {:sym, ")", _, _}
         | rest
       ]),
       do: {:ok, :data, [{:label, label, line, col}, {:param, name, line, col}], rest}

  defp on_kind([
         {:ident, kind, _, _},
         {:sym, "(", _, _},
         {:ident, name, line, col},
         {:sym, ")", _, _}
         | rest
       ])
       when kind in ["err", "tick", "ui"],
       do:
         {:ok, Map.fetch!(%{"err" => :err, "tick" => :tick, "ui" => :ui}, kind),
          [{:param, name, line, col}], rest}

  # Right name, wrong shape: show that header's form instead of the
  # generic list.
  defp on_kind([{:ident, name, line, col} | _])
       when name in ["init", "data", "err", "tick", "ui"] do
    case name do
      "init" -> err(line, col, "init takes no parameters: on init:")
      "data" -> err(line, col, ~s|data needs a label and a name: on data("label", name):|)
      "err" -> err(line, col, "err takes one parameter: on err(name):")
      "tick" -> err(line, col, "tick takes one parameter: on tick(name):")
      "ui" -> err(line, col, "ui takes one parameter: on ui(name):")
    end
  end

  defp on_kind([{_, _, line, col} | _]),
    do:
      err(
        line,
        col,
        "unknown handler; expected init, data(\"label\", name), err(name), tick(name) or ui(name)"
      )

  defp on_kind([]), do: err(1, 1, "incomplete handler header")

  # Every line indented past `indent`, parsed at the first child's indent.
  defp child_block([{child_indent, _, _} | _] = lines, indent) when child_indent > indent do
    {block, rest} = Enum.split_while(lines, fn {i, _, _} -> i >= child_indent end)
    {:ok, block, rest}
  end

  defp child_block([{_child_indent, line, _} | _], _indent),
    do: err(line, 1, "expected an indented block")

  defp child_block([], _), do: err(1, 1, "expected an indented block")

  defp parse_block([], _indent), do: {:ok, [], []}

  defp parse_block([{indent, _, _} | _] = lines, block_indent) when indent < block_indent,
    do: {:ok, [], lines}

  defp parse_block([{indent, _line, tokens} | rest], block_indent) when indent == block_indent do
    with {:ok, stmt, rest} <- parse_stmt(tokens, rest, block_indent),
         {:ok, more, rest} <- parse_block(rest, block_indent) do
      {:ok, [stmt | more], rest}
    end
  end

  defp parse_block([{indent, line, _} | _], block_indent) when indent > block_indent,
    do: err(line, indent + 1, "unexpected indent")

  # ------------------------------------------------------------ statements

  defp parse_stmt([{:ident, "if", _, _} | tokens], rest, indent),
    do: parse_if(tokens, rest, indent)

  defp parse_stmt([{:ident, "else", _, line} | _], _rest, _indent),
    do: err(line, 1, "else without a matching if")

  defp parse_stmt([{:ident, "match", l, c} | tokens], rest, indent),
    do: parse_match(tokens, rest, indent, l, c)

  defp parse_stmt([{:ident, "when", _, line} | _], _rest, _indent),
    do: err(line, 1, "when outside a match")

  defp parse_stmt(
         [{:ident, "let", l, c}, {:ident, name, _, _}, {:sym, "=", _, _} | tokens],
         rest,
         _
       ) do
    with {:ok, expr, tokens} <- parse_expr(tokens),
         {:ok, []} <- expect_end(tokens) do
      {:ok, {:let, name, expr, l, c}, rest}
    end
  end

  defp parse_stmt([{:ident, "let", _, line} | _], _rest, _),
    do: err(line, 1, "let expects: let name = expression")

  defp parse_stmt([{:ident, name, l, c}, {:sym, "=", _, _} | tokens], rest, _)
       when name != "let" do
    with {:ok, expr, tokens} <- parse_expr(tokens),
         {:ok, []} <- expect_end(tokens) do
      {:ok, {:assign, name, expr, l, c}, rest}
    end
  end

  defp parse_stmt([{:ident, kw, l, c} | tokens], rest, _)
       when kw in ["print", "render", "animate"] do
    with {:ok, _, tokens} <- expect_sym(tokens, "("),
         {:ok, expr, tokens} <- parse_expr(tokens),
         {:ok, _, tokens} <- expect_sym(tokens, ")"),
         {:ok, []} <- expect_end(tokens) do
      {:ok,
       {Map.fetch!(%{"print" => :print, "render" => :render, "animate" => :animate}, kw), expr, l,
        c}, rest}
    end
  end

  defp parse_stmt([{:ident, "draw", l, c}, {:sym, "[", _, _} | tokens], rest, _) do
    with {:ok, items, tokens} <- parse_draw_items(tokens, l, c),
         {:ok, []} <- expect_end(tokens) do
      {:ok, {:draw, items, l, c}, rest}
    end
  end

  defp parse_stmt(
         [{:ident, "want", l, c}, {:str, label, _, _}, {:sym, "=", _, _} | tokens],
         rest,
         _
       ) do
    with {:ok, op, args, tokens} <- parse_host_call(tokens),
         {:ok, []} <- expect_end(tokens) do
      {:ok, {:want, label, op, args, l, c}, rest}
    end
  end

  defp parse_stmt([{:ident, "want", _, line} | _], _rest, _),
    do: err(line, 1, ~s|want expects: want "label" = op(name: value, …)|)

  defp parse_stmt([{:ident, name, line, col} | _], _rest, _),
    do: err(line, col, "not a statement (saw #{name})")

  defp parse_stmt([{kind, _, line, col} | _], _rest, _),
    do: err(line, col, "not a statement (saw #{kind})")

  defp parse_stmt([], _, _), do: err(1, 1, "expected a statement")

  defp parse_draw_items([{:sym, "]", _, _} | rest], _l, _c), do: {:ok, [], rest}

  defp parse_draw_items(tokens, l, c) do
    with {:ok, item, tokens} <- parse_primary(tokens),
         {:ok, item} <- require_call(item) do
      parse_draw_rest(item, tokens, l, c)
    end
  end

  defp parse_draw_rest(item, [{:sym, ",", _, _} | rest], l, c) do
    with {:ok, more, rest} <- parse_draw_items(rest, l, c), do: {:ok, [item | more], rest}
  end

  defp parse_draw_rest(item, [{:sym, "]", _, _} | rest], _l, _c), do: {:ok, [item], rest}

  defp parse_draw_rest(_item, [{_, _, line, col} | _], _l, _c),
    do: err(line, col, "expected , or ] in the draw list")

  defp parse_draw_rest(_item, [], l, c), do: err(l, c, "unterminated draw list (expected ])")

  defp require_call({:call, _, _, _} = call), do: {:ok, call}

  defp require_call({:var, name, {line, col}}),
    do: err(line, col, "draw entries must be calls: #{name}(...)")

  defp require_call({_, _, line, col}), do: err(line, col, "draw entries must be calls")

  # parse_named_args eats the closing paren itself, along with the empty
  # `()` case, so nothing is left to expect here.
  defp parse_host_call([{:ident, name, l, c} | tokens]) do
    with {:ok, _, tokens} <- expect_sym(tokens, "("),
         {:ok, args, tokens} <- parse_named_args(tokens, l, c) do
      {:ok, name, args, tokens}
    end
  end

  defp parse_host_call([{_, _, line, col} | _]),
    do: err(line, col, "expected a host operation name")

  defp parse_host_call([]), do: err(1, 1, "expected a host operation")

  defp parse_named_args([{:sym, ")", _, _} | rest], _l, _c), do: {:ok, [], rest}

  defp parse_named_args(tokens, l, c) do
    with {:ok, name, tokens} <- expect_ident(tokens, "an argument name"),
         {:ok, _, tokens} <- expect_sym(tokens, ":"),
         {:ok, expr, tokens} <- parse_expr(tokens) do
      parse_named_rest(name, expr, tokens, l, c)
    end
  end

  defp parse_named_rest(name, expr, [{:sym, ",", _, _} | rest], l, c) do
    with {:ok, more, rest} <- parse_named_args(rest, l, c),
         do: {:ok, [{name, expr} | more], rest}
  end

  defp parse_named_rest(name, expr, [{:sym, ")", _, _} | rest], _l, _c),
    do: {:ok, [{name, expr}], rest}

  defp parse_named_rest(_name, _expr, [{_, _, line, col} | _], _l, _c),
    do: err(line, col, "expected , or )")

  defp parse_named_rest(_name, _expr, [], l, c), do: err(l, c, "unterminated argument list")

  defp parse_if(tokens, rest, indent) do
    with {:ok, cond_expr, tokens} <- parse_expr(tokens),
         {:ok, _colon, tokens} <- expect_sym(tokens, ":"),
         {:ok, []} <- expect_end(tokens),
         {:ok, then_block, after_then} <- child_block(rest, indent),
         {:ok, then_body, []} <- parse_block(then_block, hd_block_indent(then_block)) do
      parse_if_tail(indent, cond_expr, then_body, after_then)
    end
  end

  defp parse_if_tail(
         indent,
         cond_expr,
         then_body,
         [{else_indent, _, [{:ident, "else", _, _}, {:sym, ":", _, _} | tail]} | more]
       )
       when else_indent == indent do
    with {:ok, []} <- expect_end(tail),
         {:ok, else_block, after_else} <- child_block(more, indent),
         {:ok, else_body, []} <- parse_block(else_block, hd_block_indent(else_block)) do
      {:ok, {:if, cond_expr, then_body, else_body}, after_else}
    end
  end

  defp parse_if_tail(
         indent,
         _cond_expr,
         _then_body,
         [{else_indent, _, [{:ident, "else", _, line} | _]} | _]
       )
       when else_indent == indent do
    err(line, 1, "else must be followed by : and an indented block")
  end

  defp parse_if_tail(_indent, cond_expr, then_body, after_then),
    do: {:ok, {:if, cond_expr, then_body, nil}, after_then}

  defp parse_match(tokens, rest, indent, l, c) do
    with {:ok, subject, tokens} <- parse_expr(tokens),
         {:ok, _colon, tokens} <- expect_sym(tokens, ":"),
         {:ok, []} <- expect_end(tokens),
         {:ok, arms, else_arm, rest} <- match_arms(rest, indent) do
      if arms == [] do
        err(l, c, "match needs at least one when: arm")
      else
        {:ok, {:match, subject, arms, else_arm}, rest}
      end
    end
  end

  defp match_arms([{child_indent, _, _} | _] = lines, indent)
       when child_indent > indent do
    parse_arms(lines, child_indent, [], nil)
  end

  defp match_arms(_lines, _indent),
    do: err(1, 1, "expected an indented block under match")

  defp parse_arms([], _arm_indent, arms, else_arm),
    do: {:ok, Enum.reverse(arms), else_arm, []}

  defp parse_arms([{first, line, tokens} | rest] = lines, arm_indent, arms, else_arm) do
    cond do
      first < arm_indent ->
        {:ok, Enum.reverse(arms), else_arm, lines}

      first > arm_indent ->
        err(line, first + 1, "unexpected indent in match (expected #{arm_indent})")

      true ->
        parse_arm(tokens, line, rest, arm_indent, arms, else_arm)
    end
  end

  defp parse_arm(tokens, line, rest, arm_indent, arms, else_arm) do
    case tokens do
      [{:ident, "when", _, _}, lit, {:sym, ":", _, _} | tail] ->
        with {:ok, literal} <- when_literal(lit),
             {:ok, []} <- expect_end(tail),
             {:ok, block, after_block} <- child_block(rest, arm_indent),
             {:ok, body, []} <- parse_block(block, hd_block_indent(block)) do
          parse_arms(after_block, arm_indent, [{literal, body} | arms], else_arm)
        end

      [{:ident, "else", _, _}, {:sym, ":", _, _} | tail] ->
        with {:ok, []} <- expect_end(tail),
             {:ok, block, after_block} <- child_block(rest, arm_indent),
             {:ok, body, []} <- parse_block(block, hd_block_indent(block)) do
          parse_arms(after_block, arm_indent, arms, {:else, body})
        end

      [{:ident, "when", _, wl} | _] ->
        err(wl, 1, "when expects a literal: a number, string, true, false or null")

      [{:ident, other, _, c} | _] ->
        err(line, c, "expected when or else in match (saw #{other})")

      [] ->
        err(line, arm_indent + 1, "empty line in match")
    end
  end

  defp when_literal({:num, n, _, _}), do: {:ok, {:num, n}}
  defp when_literal({:str, s, _, _}), do: {:ok, {:str, s}}
  defp when_literal({:ident, "true", _, _}), do: {:ok, {:bool, true}}
  defp when_literal({:ident, "false", _, _}), do: {:ok, {:bool, false}}
  defp when_literal({:ident, "null", _, _}), do: {:ok, {:null}}
  defp when_literal({_, _, line, col}), do: err(line, col, "when expects a literal value")

  # ============================================================= expression

  defp parse_expr(tokens), do: parse_or(tokens)

  # The five levels share one shape: parse the left side, then look at the
  # next token in a dedicated clause so no level nests a control structure
  # inside another.
  defp parse_or(tokens) do
    with {:ok, left, tokens} <- parse_and(tokens), do: parse_or(left, tokens)
  end

  defp parse_or(left, [{:ident, "or", _, _} | rest]) do
    with {:ok, right, rest} <- parse_or(rest), do: {:ok, {:bin, :or, left, right}, rest}
  end

  defp parse_or(left, tokens), do: {:ok, left, tokens}

  defp parse_and(tokens) do
    with {:ok, left, tokens} <- parse_cmp(tokens), do: parse_and(left, tokens)
  end

  defp parse_and(left, [{:ident, "and", _, _} | rest]) do
    with {:ok, right, rest} <- parse_and(rest), do: {:ok, {:bin, :and, left, right}, rest}
  end

  defp parse_and(left, tokens), do: {:ok, left, tokens}

  defp parse_cmp(tokens) do
    with {:ok, left, tokens} <- parse_add(tokens), do: parse_cmp(left, tokens)
  end

  defp parse_cmp(left, [{:sym, op, _, _} | rest]) when op in ["==", "!=", "<", "<=", ">", ">="] do
    with {:ok, right, rest} <- parse_cmp(rest),
         do: {:ok, {:bin, Map.fetch!(@bin_ops, op), left, right}, rest}
  end

  defp parse_cmp(left, tokens), do: {:ok, left, tokens}

  defp parse_add(tokens) do
    with {:ok, left, tokens} <- parse_mul(tokens), do: parse_add(left, tokens)
  end

  defp parse_add(left, [{:sym, op, _, _} | rest]) when op in ["+", "-"] do
    with {:ok, right, rest} <- parse_add(rest),
         do: {:ok, {:bin, Map.fetch!(@bin_ops, op), left, right}, rest}
  end

  defp parse_add(left, tokens), do: {:ok, left, tokens}

  defp parse_mul(tokens) do
    with {:ok, left, tokens} <- parse_unary(tokens), do: parse_mul(left, tokens)
  end

  defp parse_mul(left, [{:sym, op, _, _} | rest]) when op in ["*", "/", "%"] do
    with {:ok, right, rest} <- parse_mul(rest),
         do: {:ok, {:bin, Map.fetch!(@bin_ops, op), left, right}, rest}
  end

  defp parse_mul(left, tokens), do: {:ok, left, tokens}

  defp parse_unary([{:sym, "-", _, _} | rest]) do
    with {:ok, inner, rest} <- parse_unary(rest) do
      {:ok, {:neg, inner}, rest}
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  defp parse_primary([{:num, n, _, _} | rest]), do: {:ok, {:num, n}, rest}
  defp parse_primary([{:str, s, _, _} | rest]), do: {:ok, {:str, s}, rest}

  defp parse_primary([{:ident, name, _, _} | rest]) when name in ["true", "false"],
    do: {:ok, {:bool, name == "true"}, rest}

  defp parse_primary([{:ident, "null", _, _} | rest]), do: {:ok, {:null}, rest}

  defp parse_primary([{:sym, "[", _, _} | rest]) do
    with {:ok, items, rest} <- parse_array_items(rest, []) do
      {:ok, {:array, items}, rest}
    end
  end

  defp parse_primary([{:sym, "(", _, _} | rest]) do
    with {:ok, inner, rest} <- parse_expr(rest),
         {:ok, _, rest} <- expect_sym(rest, ")") do
      {:ok, inner, rest}
    end
  end

  defp parse_primary([{:ident, name, line, col} | rest]) do
    case rest do
      [{:sym, "(", _, _} | tail] ->
        with {:ok, args, tail} <- parse_call_args(tail) do
          {:ok, {:call, name, args, {line, col}}, tail}
        end

      _ ->
        {:ok, {:var, name, {line, col}}, rest}
    end
  end

  defp parse_primary([{_, _, line, col} | _]), do: err(line, col, "expected a value")
  defp parse_primary([]), do: err(1, 1, "unexpected end of statement")

  defp parse_call_args([{:sym, ")", _, _} | rest]), do: {:ok, {:pos, []}, rest}

  defp parse_call_args([{:ident, _name, _, _}, {:sym, ":", _, _} | _] = tokens),
    do: parse_named_list(tokens, [])

  defp parse_call_args(tokens), do: parse_pos_list(tokens, [])

  defp parse_pos_list([{:sym, ")", _, _} | rest], acc),
    do: {:ok, {:pos, Enum.reverse(acc)}, rest}

  defp parse_pos_list(tokens, acc) do
    with {:ok, expr, tokens} <- parse_expr(tokens) do
      case tokens do
        [{:sym, ",", _, _} | rest] -> parse_pos_list(rest, [expr | acc])
        [{:sym, ")", _, _} | rest] -> {:ok, {:pos, Enum.reverse([expr | acc])}, rest}
        [{_, _, line, col} | _] -> err(line, col, "expected , or )")
        [] -> err(1, 1, "unterminated argument list")
      end
    end
  end

  defp parse_named_list([{:sym, ")", _, _} | rest], acc),
    do: {:ok, {:named, Enum.reverse(acc)}, rest}

  defp parse_named_list(tokens, acc) do
    with {:ok, name, tokens} <- expect_ident(tokens, "an argument name"),
         {:ok, _, tokens} <- expect_sym(tokens, ":"),
         {:ok, expr, tokens} <- parse_expr(tokens) do
      case tokens do
        [{:sym, ",", _, _} | rest] -> parse_named_list(rest, [{name, expr} | acc])
        [{:sym, ")", _, _} | rest] -> {:ok, {:named, Enum.reverse([{name, expr} | acc])}, rest}
        [{_, _, line, col} | _] -> err(line, col, "expected , or )")
        [] -> err(1, 1, "unterminated argument list")
      end
    end
  end

  defp parse_array_items([{:sym, "]", _, _} | rest], acc), do: {:ok, Enum.reverse(acc), rest}

  defp parse_array_items(tokens, acc) do
    with {:ok, expr, tokens} <- parse_expr(tokens) do
      case tokens do
        [{:sym, ",", _, _} | rest] -> parse_array_items(rest, [expr | acc])
        [{:sym, "]", _, _} | rest] -> {:ok, Enum.reverse([expr | acc]), rest}
        [{_, _, line, col} | _] -> err(line, col, "expected , or ]")
        [] -> err(1, 1, "unterminated array literal")
      end
    end
  end

  # ------------------------------------------------------------ token ends

  defp expect_sym([{:sym, s, _, _} | rest], s), do: {:ok, s, rest}

  defp expect_sym([{kind, value, line, col} | _], s),
    do: err(line, col, "expected #{s}, saw #{describe({kind, value})}")

  defp expect_sym([], s), do: err(1, 1, "expected #{s}")

  defp expect_ident([{:ident, name, _, _} | rest], _what), do: {:ok, name, rest}

  defp expect_ident([{kind, value, line, col} | _], what),
    do: err(line, col, "expected #{what}, saw #{describe({kind, value})}")

  defp expect_ident([], what), do: err(1, 1, "expected #{what}")

  defp expect_end([]), do: {:ok, []}

  defp expect_end([{kind, value, line, col} | _]),
    do: err(line, col, "unexpected #{describe({kind, value})} after the statement")

  defp describe({:ident, name}), do: name
  defp describe({:sym, s}), do: s
  defp describe({:num, n}), do: to_string(n)
  defp describe({:str, _}), do: "a string"
  defp describe({kind, _}), do: to_string(kind)

  # ================================================================= check

  # The plan the emitter reads: handlers with their scopes, the constant
  # pool, label→ref wiring, and the two size guards (pool ≤ 0x1000, effect
  # sites ≤ elist capacity).
  defp check(handlers) do
    state = %{
      pool: Map.new(@abi_strings, &{&1, nil}),
      order: [],
      next: 112,
      refs: %{},
      data_labels: MapSet.new(),
      kinds: MapSet.new(),
      max_effects: 0
    }

    state = Enum.reduce(@abi_strings, state, &intern(&2, &1))

    with {:ok, state} <- claim_labels(handlers, state),
         {:ok, checked, state} <- check_handlers(handlers, state),
         {:ok, _} <- check_init(handlers),
         {:ok, state} <- finish_sizes(checked, state) do
      {:ok,
       %{
         handlers: checked,
         pool: state.pool,
         order: Enum.reverse(state.order),
         next: state.next,
         refs: state.refs,
         max_effects: state.max_effects
       }}
    end
  end

  # Every data label is registered before any body is checked, so a want in
  # `on init:` can name a label whose handler appears later in the file.
  defp claim_labels([], state), do: {:ok, state}

  defp claim_labels([{:on, :data, [{:label, label, line, col} | _], _} | rest], state) do
    if MapSet.member?(state.data_labels, label) do
      err(line, col, "duplicate data label #{inspect(label)}")
    else
      claim_labels(rest, %{
        state
        | data_labels: MapSet.put(state.data_labels, label),
          refs: Map.put(state.refs, label, map_size(state.refs) + 1)
      })
    end
  end

  defp claim_labels([_ | rest], state), do: claim_labels(rest, state)

  defp check_init(handlers) do
    case Enum.count(handlers, &match?({:on, :init, _, _}, &1)) do
      0 -> err(1, 1, "on init: is required")
      1 -> {:ok, :init}
      _ -> err(1, 1, "on init: appears more than once")
    end
  end

  defp check_handlers([], state), do: {:ok, [], state}

  defp check_handlers([{:on, kind, params, body} | rest], state) do
    with :ok <- check_param_words(params),
         {:ok, state} <- check_handler_kind(kind, params, state),
         scope = scope_of(params),
         {:ok, body, body_scope, effects, state} <- check_stmts(body, scope, state, 0),
         {:ok, more, state} <- check_handlers(rest, state) do
      handler = %{
        kind: kind,
        params: param_names(params),
        body: body,
        locals: Enum.uniq(body_scope.local_order),
        effects: effects,
        ref: Map.get(state.refs, label_of(kind, params), 0)
      }

      {:ok, [handler | more], %{state | max_effects: max(state.max_effects, effects)}}
    end
  end

  # A handler parameter becomes a local binding, so it takes the same
  # reserved-word rule as `let`, plus uniqueness inside one handler.
  defp check_param_words(params), do: check_param_words(params, MapSet.new())

  defp check_param_words([{:label, _, _, _} | rest], seen),
    do: check_param_words(rest, seen)

  defp check_param_words([{:param, name, line, col} | rest], seen) do
    cond do
      name in @reserved ->
        err(line, col, "#{name} is a reserved word")

      MapSet.member?(seen, name) ->
        err(line, col, "duplicate parameter #{name}")

      true ->
        check_param_words(rest, MapSet.put(seen, name))
    end
  end

  defp check_param_words([], _seen), do: :ok

  # Labels and their refs were claimed up front; nothing left to record.
  defp check_handler_kind(:data, _params, state), do: {:ok, state}

  defp check_handler_kind(kind, _, state) when kind in [:init, :err, :tick, :ui] do
    if MapSet.member?(state.kinds, kind) do
      err(1, 1, "duplicate #{kind} handler")
    else
      {:ok, %{state | kinds: MapSet.put(state.kinds, kind)}}
    end
  end

  defp scope_of(params) do
    names = param_names(params)
    %{vars: MapSet.new(names), local_order: names}
  end

  defp param_names(params), do: for({:param, name, _, _} <- params, do: name)
  defp label_of(:data, [{:label, label, _, _} | _]), do: label
  defp label_of(_, _), do: nil

  defp check_stmts([], scope, state, effects), do: {:ok, [], scope, effects, state}

  defp check_stmts([stmt | rest], scope, state, effects) do
    with {:ok, stmt, scope, added, state} <- check_stmt(stmt, scope, state),
         {:ok, more, scope, effects, state} <- check_stmts(rest, scope, state, effects + added) do
      {:ok, [stmt | more], scope, effects, state}
    end
  end

  defp check_stmt({:let, name, expr, line, col}, scope, state) do
    cond do
      MapSet.member?(scope.vars, name) ->
        err(line, col, "#{name} is already defined")

      name in @reserved ->
        err(line, col, "#{name} is a reserved word")

      true ->
        with {:ok, expr, state} <- check_expr(expr, scope, state) do
          scope = %{
            scope
            | vars: MapSet.put(scope.vars, name),
              local_order: scope.local_order ++ [name]
          }

          {:ok, {:let, name, expr, line, col}, scope, 0, state}
        end
    end
  end

  defp check_stmt({:assign, name, expr, line, col}, scope, state) do
    if MapSet.member?(scope.vars, name) do
      with {:ok, expr, state} <- check_expr(expr, scope, state) do
        {:ok, {:assign, name, expr, line, col}, scope, 0, state}
      end
    else
      err(line, col, "#{name} is not defined (let #{name} = … first)")
    end
  end

  defp check_stmt({:print, expr, line, col}, scope, state) do
    with {:ok, expr, state} <- check_expr(expr, scope, state) do
      {:ok, {:print, expr, line, col}, scope, 1, state}
    end
  end

  defp check_stmt({:animate, expr, line, col}, scope, state) do
    with {:ok, expr, state} <- check_expr(expr, scope, state) do
      {:ok, {:animate, expr, line, col}, scope, 1, state}
    end
  end

  defp check_stmt({:render, expr, line, col}, scope, state) do
    with :ok <- check_view(expr),
         {:ok, expr, state} <- check_expr(expr, scope, state) do
      {:ok, {:render, expr, line, col}, scope, 1, state}
    end
  end

  defp check_stmt({:draw, items, line, col}, scope, state) do
    with {:ok, items, state} <- check_draw_items(items, scope, state) do
      {:ok, {:draw, items, line, col}, scope, 1, state}
    end
  end

  defp check_stmt({:want, label, op, args, line, col}, scope, state) do
    with :ok <- check_want_label(label, line, col, state),
         :ok <- check_want_op(op, args, line, col) do
      case check_expr_list(args, scope, intern(state, op)) do
        {:ok, args, state} ->
          {:ok, {:want, label, op, args, line, col}, scope, 1, state}

        {:error, _} = error ->
          error
      end
    end
  end

  defp check_stmt({:if, cond_expr, then_body, else_body}, scope, state) do
    with {:ok, cond_expr, state} <- check_expr(cond_expr, scope, state),
         {:ok, then_body, then_scope, t_eff, state} <- check_stmts(then_body, scope, state, 0) do
      check_if_tail(cond_expr, then_body, then_scope, t_eff, else_body, scope, state)
    end
  end

  defp check_stmt({:match, subject, arms, else_arm}, scope, state) do
    with {:ok, subject, state} <- check_expr(subject, scope, state),
         {:ok, arms, eff, state, scopes} <- check_arms(arms, scope, state) do
      check_match_tail(subject, arms, eff, scopes, else_arm, scope, state)
    end
  end

  defp check_expr_list(args, scope, state) do
    Enum.reduce_while(args, {:ok, [], state}, fn {name, expr}, {:ok, acc, st} ->
      case check_expr(expr, scope, st) do
        {:ok, expr, st} -> {:cont, {:ok, [{name, expr} | acc], st}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, args, state} -> {:ok, Enum.reverse(args), state}
      {:error, _} = error -> error
    end
  end

  defp check_if_tail(cond_expr, then_body, then_scope, t_eff, nil, scope, state) do
    {:ok, {:if, cond_expr, then_body, nil}, absorb(scope, then_scope), t_eff, state}
  end

  defp check_if_tail(cond_expr, then_body, then_scope, t_eff, else_body, scope, state) do
    with {:ok, else_body, else_scope, e_eff, state} <- check_stmts(else_body, scope, state, 0) do
      merged = scope |> absorb(then_scope) |> absorb(else_scope)
      {:ok, {:if, cond_expr, then_body, else_body}, merged, t_eff + e_eff, state}
    end
  end

  defp check_match_tail(subject, arms, eff, scopes, nil, scope, state) do
    {:ok, {:match, subject, arms, nil}, absorb_all(scope, scopes), eff, state}
  end

  defp check_match_tail(subject, arms, eff, scopes, {:else, body}, scope, state) do
    with {:ok, body, else_scope, e_eff, state} <- check_stmts(body, scope, state, 0) do
      merged = absorb_all(scope, [else_scope | scopes])

      {:ok, {:match, subject, arms, {:else, body}}, merged, eff + e_eff, state}
    end
  end

  defp check_arms(arms, scope, state) do
    Enum.reduce_while(arms, {:ok, [], 0, state, []}, fn {lit, body},
                                                        {:ok, acc, eff, st, scopes} ->
      st =
        case lit do
          {:str, s} -> intern(st, s)
          _ -> st
        end

      case check_stmts(body, scope, st, 0) do
        {:ok, body, arm_scope, e, st} ->
          {:cont, {:ok, [{lit, body} | acc], eff + e, st, [arm_scope | scopes]}}

        {:error, _} = error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, arms, eff, state, scopes} -> {:ok, Enum.reverse(arms), eff, state, scopes}
      {:error, _} = error -> error
    end
  end

  # Branch scopes never leak names upward, but every `let` anywhere in the
  # handler becomes one flat local at the top of the emitted function.
  defp absorb(scope, branch) do
    %{scope | local_order: Enum.uniq(scope.local_order ++ branch.local_order)}
  end

  defp absorb_all(scope, branches), do: Enum.reduce(branches, scope, &absorb(&2, &1))

  defp check_want_label(label, line, col, state) do
    if Map.has_key?(state.refs, label) do
      :ok
    else
      err(
        line,
        col,
        ~s|unknown data label #{inspect(label)} (declare on data("#{label}", …) first)|
      )
    end
  end

  # ---- views: render's argument must be a view-shaped call tree.

  defp check_view({:call, name, {:pos, args}, _at}) when name in ["col", "row"] do
    Enum.reduce_while(args, :ok, fn kid, _ ->
      case check_view(kid) do
        :ok -> {:cont, :ok}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  # text and canvas take expressions, not nested views; check_expr walks them.
  defp check_view({:call, name, {:pos, args}, at}) when name in @view_builds do
    {line, col} = at
    check_view_arity(name, Map.get(@view_arity, name, :any), length(args), line, col)
  end

  defp check_view({:call, name, {:named, _}, {line, col}}),
    do: err(line, col, "#{name} takes positional arguments in a view")

  defp check_view({:var, name, {line, col}}),
    do: err(line, col, "render expects a view, not the variable #{name}")

  defp check_view({_, _, line, col}) when is_integer(line) and is_integer(col),
    do: err(line, col, "render expects a view (text, col, row or canvas)")

  # Literals, operators, arrays: right verdict, no position to point at.
  defp check_view(_),
    do: err(1, 1, "render expects a view (text, col, row or canvas)")

  defp check_view_arity(_name, :any, _given, _line, _col), do: :ok

  defp check_view_arity(name, expected, given, line, col) when expected != given,
    do: err(line, col, "#{name} takes #{expected} argument(s), got #{given}")

  defp check_view_arity(_name, _expected, _given, _line, _col), do: :ok

  # ---- draw lists.

  defp check_draw_items([], _scope, state), do: {:ok, [], state}

  defp check_draw_items([{:call, name, args, at} | rest], scope, state) do
    with {:ok, spec} <- draw_spec(name, at),
         {:ok, args, state} <- check_draw_args(name, spec, args, scope, state, at) do
      state = intern(state, name)

      case check_draw_items(rest, scope, state) do
        {:ok, more, state} -> {:ok, [{:call, name, args, at} | more], state}
        {:error, _} = error -> error
      end
    end
  end

  defp draw_spec(name, {line, col}) do
    case Map.fetch(@draw_ops, name) do
      {:ok, spec} ->
        {:ok, spec}

      :error ->
        if name in @view_builds do
          err(line, col, "#{name} builds a view; it cannot be drawn (did you mean render?)")
        else
          err(line, col, "unknown draw op #{name}")
        end
    end
  end

  defp check_draw_args(name, _spec, {:pos, _}, _scope, _state, {line, col}),
    do:
      err(
        line,
        col,
        "#{name} takes named arguments (#{Enum.join(Map.fetch!(@draw_ops, name).req, ": …, ")}: …)"
      )

  defp check_draw_args(name, spec, {:named, args}, scope, state, {line, col}) do
    given = Enum.map(args, &elem(&1, 0))
    known = spec.req ++ spec.opt

    cond do
      Enum.uniq(given) != given ->
        err(line, col, "#{name} has a duplicate argument")

      unknown = Enum.find(given, &(&1 not in known)) ->
        err(line, col, "#{name} has no argument #{unknown}")

      missing = Enum.find(spec.req, &(&1 not in given)) ->
        err(line, col, "#{name} is missing #{missing}")

      true ->
        with {:ok, args, state} <- check_expr_list(args, scope, state) do
          {:ok, {:named, args}, state}
        end
    end
  end

  defp check_want_op(op, args, line, col) do
    case Map.fetch(@host_ops, op) do
      :error ->
        err(line, col, "unknown host operation #{op}")

      {:ok, spec} ->
        names = Enum.map(args, &elem(&1, 0))

        cond do
          Enum.uniq(names) != names ->
            err(line, col, "#{op} has a duplicate argument")

          unknown = Enum.find(names, &(&1 not in (spec.req ++ spec.opt))) ->
            err(line, col, "#{op} has no argument #{unknown}")

          missing = Enum.find(spec.req, &(&1 not in names)) ->
            err(line, col, "#{op} is missing #{missing}")

          true ->
            :ok
        end
    end
  end

  # ---- expressions.

  defp check_expr({:num, n}, _scope, state), do: {:ok, {:num, n}, state}
  defp check_expr({:bool, b}, _scope, state), do: {:ok, {:bool, b}, state}
  defp check_expr({:null}, _scope, state), do: {:ok, {:null}, state}

  # Strings stay as their source text all the way to emit; interning just
  # reserves the pool slot so the size checks see them.
  defp check_expr({:str, s}, _scope, state), do: {:ok, {:str, s}, intern(state, s)}

  defp check_expr({:var, name, {line, col}}, scope, state) do
    if MapSet.member?(scope.vars, name) do
      {:ok, {:var, name, {line, col}}, state}
    else
      err(line, col, "#{name} is not defined")
    end
  end

  defp check_expr({:array, items}, scope, state) do
    with {:ok, items, state} <- map_args(items, scope, state) do
      {:ok, {:array, items}, state}
    end
  end

  defp check_expr({:neg, inner}, scope, state) do
    with {:ok, inner, state} <- check_expr(inner, scope, state) do
      {:ok, {:neg, inner}, state}
    end
  end

  defp check_expr({:bin, op, l, r}, scope, state) do
    with {:ok, l, state} <- check_expr(l, scope, state),
         {:ok, r, state} <- check_expr(r, scope, state) do
      {:ok, {:bin, op, l, r}, state}
    end
  end

  defp check_expr({:call, name, args, at}, scope, state) do
    cond do
      # Before the draw-op arm: `text` is both a view build and a draw op,
      # and in expression position only the view reading is legal.
      name in @view_builds ->
        with {:ok, args, state} <- view_args(name, args, scope, state, at) do
          {:ok, {:call, name, args, at}, state}
        end

      Map.has_key?(@host_ops, name) ->
        {line, col} = at
        err(line, col, "#{name} is used inside want \"label\" = #{name}(…)")

      Map.has_key?(@draw_ops, name) ->
        {line, col} = at
        err(line, col, "#{name} can only be used inside draw [...]")

      Map.has_key?(@builtin_arity, name) ->
        arity = Map.fetch!(@builtin_arity, name)

        with {:ok, args, state} <- positional_args(name, args, arity, scope, state, at) do
          {:ok, {:call, name, args, at}, state}
        end

      true ->
        {line, col} = at
        err(line, col, "unknown function #{name}")
    end
  end

  defp view_args(name, {:named, _}, _scope, _state, {line, col}) do
    err(line, col, "#{name} takes positional arguments")
  end

  defp view_args(name, {:pos, args}, scope, state, {line, col}) do
    arity = Map.get(@view_arity, name)

    if arity != nil and length(args) != arity do
      err(line, col, "#{name} takes #{arity} argument(s), got #{length(args)}")
    else
      with {:ok, args, state} <- map_args(args, scope, state) do
        {:ok, {:pos, args}, state}
      end
    end
  end

  defp positional_args(name, {:pos, args}, arity, scope, state, {line, col}) do
    if length(args) == arity do
      with {:ok, args, state} <- map_args(args, scope, state) do
        {:ok, {:pos, args}, state}
      end
    else
      err(line, col, "#{name} takes #{arity} argument(s), got #{length(args)}")
    end
  end

  defp positional_args(name, {:named, _}, _arity, _scope, _state, {line, col}) do
    err(line, col, "#{name} takes positional arguments")
  end

  # Walk a list of expressions, stopping at the first error instead of
  # raising out of the reduce.
  defp map_args(args, scope, state) do
    args
    |> Enum.reduce_while({:ok, [], state}, fn expr, {:ok, acc, st} ->
      case check_expr(expr, scope, st) do
        {:ok, expr, st} -> {:cont, {:ok, [expr | acc], st}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, acc, state} -> {:ok, Enum.reverse(acc), state}
      {:error, _} = error -> error
    end
  end

  defp intern(%{pool: pool} = state, str) do
    case Map.fetch(pool, str) do
      {:ok, nil} ->
        addr = state.next

        %{
          state
          | pool: Map.put(pool, str, addr),
            order: [str | state.order],
            next: addr + align8(8 + byte_size(str))
        }

      {:ok, _addr} ->
        state

      :error ->
        addr = state.next

        %{
          state
          | pool: Map.put(state.pool, str, addr),
            order: [str | state.order],
            next: addr + align8(8 + byte_size(str))
        }
    end
  end

  defp align8(n), do: Bitwise.band(n + 7, -8)

  defp finish_sizes(checked, state) do
    pool_end = state.next
    capacity = div(0x1000 - pool_end, 4)
    worst = checked |> Enum.map(& &1.effects) |> Enum.max(fn -> 0 end)

    cond do
      pool_end > 0x1000 -> err(1, 1, "constant pool too large")
      worst > capacity -> err(1, 1, "too many effects for one turn")
      true -> {:ok, %{state | max_effects: worst}}
    end
  end

  # ================================================================== emit

  defp emit(plan) do
    handlers = Enum.map_join(plan.handlers, "\n", &emit_handler(&1, plan))
    pool = Enum.map_join(plan.order, "\n", &emit_pool_line(&1, plan))

    """
    (module
      (memory (export "memory") 1)
    #{Runtime.source()}
    #{Runtime.data()}
    #{pool}
    #{handlers}
    #{emit_handle(plan)}
    )
    """
  end

  defp emit_pool_line(str, plan) do
    addr = Map.fetch!(plan.pool, str)
    header = <<4, 0, 0, 0, byte_size(str)::little-32>>
    "  (data (i32.const #{addr}) \"#{escape_wat(header <> str)}\")"
  end

  defp escape_wat(binary) do
    for <<b <- binary>> do
      if b in 0x20..0x7E and b not in [?", ?\\] do
        <<b>>
      else
        "\\" <> Base.encode16(<<b>>, case: :lower)
      end
    end
    |> IO.iodata_to_binary()
  end

  defp emit_handler(handler, plan) do
    {body, ctx} = emit_stmts(handler.body, %{plan: plan, temp: 0, ind: 4})
    body = List.flatten(body)
    params = Enum.map_join(handler.params, " ", &"(param $L_#{&1} i32)")

    var_locals =
      (handler.locals -- handler.params)
      |> Enum.map(&"(local $L_#{&1} i32)")

    temps = for i <- 0..(ctx.temp - 1)//1, do: "(local $t#{i} i32)"
    decls = var_locals ++ temps
    name = handler_name(handler)

    decl_lines =
      case decls do
        [] -> []
        _ -> ["  " <> Enum.join(decls, " ")]
      end

    Enum.join(["  (func $#{name}#{params}"] ++ decl_lines ++ body ++ ["  )"], "\n")
  end

  defp handler_name(%{kind: :init}), do: "h_init"
  defp handler_name(%{kind: :data, ref: ref}), do: "h_data_#{ref}"
  defp handler_name(%{kind: kind}), do: "h_#{kind}"

  defp indent(ctx), do: String.duplicate(" ", ctx.ind)

  defp emit_stmts(stmts, ctx), do: Enum.map_reduce(stmts, ctx, &emit_stmt/2)

  defp emit_stmt({:let, name, expr, _, _}, ctx) do
    {pre, res, ctx} = emit_expr(expr, ctx)
    {pre ++ ["#{indent(ctx)}(local.set $L_#{name} #{res})"], ctx}
  end

  defp emit_stmt({:assign, name, expr, _, _}, ctx) do
    {pre, res, ctx} = emit_expr(expr, ctx)
    {pre ++ ["#{indent(ctx)}(local.set $L_#{name} #{res})"], ctx}
  end

  defp emit_stmt({:print, expr, _, _}, ctx) do
    {pre, res, ctx} = emit_expr(expr, ctx)

    {lines, ctx} =
      emit_effect(
        [{pool(ctx, "do"), pool(ctx, "print")}, {pool(ctx, "text"), "(call $v_show #{res})"}],
        ctx
      )

    {pre ++ lines, ctx}
  end

  defp emit_stmt({:render, expr, _, _}, ctx) do
    {pre, res, ctx} = emit_expr(expr, ctx)

    {lines, ctx} =
      emit_effect([{pool(ctx, "do"), pool(ctx, "render")}, {pool(ctx, "view"), res}], ctx)

    {pre ++ lines, ctx}
  end

  defp emit_stmt({:animate, expr, _, _}, ctx) do
    {pre, res, ctx} = emit_expr(expr, ctx)

    {lines, ctx} =
      emit_effect(
        [
          {pool(ctx, "do"), pool(ctx, "animate")},
          {pool(ctx, "on"), "(call $make_bool (call $truthy #{res}))"}
        ],
        ctx
      )

    {pre ++ lines, ctx}
  end

  defp emit_stmt({:draw, items, _, _}, ctx) do
    {ops, ctx} = fresh(ctx)

    setup = [
      "#{indent(ctx)}(local.set #{ops} (call $arr_new (i32.const #{length(items)})))"
    ]

    {item_lines, ctx} =
      items
      |> Enum.with_index()
      |> Enum.map_reduce(ctx, fn {item, index}, ctx ->
        emit_draw_item(item, index, ops, ctx)
      end)

    {lines, ctx} =
      emit_effect(
        [{pool(ctx, "do"), pool(ctx, "draw")}, {pool(ctx, "ops"), "(local.get #{ops})"}],
        ctx
      )

    {setup ++ List.flatten(item_lines) ++ lines, ctx}
  end

  defp emit_stmt({:want, label, op, args, _, _}, ctx) do
    {t_args, ctx} = fresh(ctx)

    {arg_pres, arg_sets, ctx} =
      args
      |> Enum.with_index()
      |> Enum.reduce({[], [], ctx}, fn {{name, expr}, slot}, {pres, sets, ctx} ->
        {pre, res, ctx} = emit_expr(expr, ctx)

        sets = [
          "#{indent(ctx)}(call $map_set (local.get #{t_args}) (i32.const #{slot}) #{pool(ctx, name)} #{res})"
          | sets
        ]

        {pres ++ pre, sets, ctx}
      end)

    setup_args = [
      "#{indent(ctx)}(local.set #{t_args} (call $map_new (i32.const #{length(args)})))"
    ]

    ref = Map.fetch!(ctx.plan.refs, label)

    {lines, ctx} =
      emit_effect(
        [
          {pool(ctx, "do"), pool(ctx, "want")},
          {pool(ctx, "ref"), "(call $make_num (f64.const #{ref}))"},
          {pool(ctx, "op"), pool(ctx, op)},
          {pool(ctx, "args"), "(local.get #{t_args})"}
        ],
        ctx
      )

    {arg_pres ++ setup_args ++ Enum.reverse(arg_sets) ++ lines, ctx}
  end

  defp emit_stmt({:if, cond_expr, then_body, else_body}, ctx) do
    {pre, res, ctx} = emit_expr(cond_expr, ctx)
    {then_lines, ctx} = emit_stmts(then_body, %{ctx | ind: ctx.ind + 2})
    head = ["#{indent(ctx)}(if (call $truthy #{res})", "#{indent(ctx)}  (then"]

    case else_body do
      nil ->
        {pre ++ head ++ List.flatten(then_lines) ++ ["#{indent(ctx)}  ))"], ctx}

      _ ->
        {else_lines, ctx} = emit_stmts(else_body, %{ctx | ind: ctx.ind + 2})

        {pre ++
           head ++
           List.flatten(then_lines) ++
           ["#{indent(ctx)}  )", "#{indent(ctx)}  (else"] ++
           List.flatten(else_lines) ++ ["#{indent(ctx)}  ))"], ctx}
    end
  end

  defp emit_stmt({:match, subject, arms, else_arm}, ctx) do
    {pre, res, ctx} = emit_expr(subject, ctx)
    {t, ctx} = fresh(ctx)
    park = ["#{indent(ctx)}(local.set #{t} #{res})"]
    {lines, ctx} = emit_match_arms(Enum.reverse(arms), else_arm, t, ctx)
    {pre ++ park ++ lines, ctx}
  end

  defp emit_draw_item({:call, name, {:named, args}, _at}, index, ops, ctx) do
    spec = Map.fetch!(@draw_ops, name)

    fields =
      [{"op", {:str, name}} | args] ++
        if "c" in spec.opt and "c" not in Enum.map(args, &elem(&1, 0)) do
          [{"c", {:str, @default_color}}]
        else
          []
        end

    {t, ctx} = fresh(ctx)
    setup = ["#{indent(ctx)}(local.set #{t} (call $map_new (i32.const #{length(fields)})))"]

    {sets, ctx} =
      fields
      |> Enum.with_index()
      |> Enum.map_reduce(ctx, fn {{fname, value}, slot}, ctx ->
        {pre, res, ctx} = emit_expr(value, ctx)

        {pre ++
           [
             "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const #{slot}) #{pool(ctx, fname)} #{res})"
           ], ctx}
      end)

    store = [
      "#{indent(ctx)}(call $arr_set (local.get #{ops}) (i32.const #{index}) (local.get #{t}))"
    ]

    {setup ++ List.flatten(sets) ++ store, ctx}
  end

  # Arms arrive reversed (last arm first) so each nested else links upward.
  defp emit_match_arms([], nil, _t, ctx), do: {[], ctx}

  # Reached only as the else half the caller has already opened, so the
  # body's lines drop straight in.
  defp emit_match_arms([], {:else, body}, _t, ctx) do
    {lines, ctx} = emit_stmts(body, %{ctx | ind: ctx.ind + 2})
    {List.flatten(lines), ctx}
  end

  defp emit_match_arms([{lit, body} | rest], else_arm, t, ctx) do
    {inner, ctx} = emit_match_arms(rest, else_arm, t, %{ctx | ind: ctx.ind + 2})
    lit_box = literal_box(lit, ctx)
    {body, ctx} = emit_stmts(body, %{ctx | ind: ctx.ind + 2})

    head = [
      "#{indent(ctx)}(if (call $v_eq (local.get #{t}) #{lit_box})",
      "#{indent(ctx)}  (then"
    ]

    tail =
      case inner do
        [] ->
          ["#{indent(ctx)}  ))"]

        inner ->
          ["#{indent(ctx)}  )", "#{indent(ctx)}  (else"] ++
            inner ++ ["#{indent(ctx)}  ))"]
      end

    {head ++ List.flatten(body) ++ tail, ctx}
  end

  defp literal_box({:num, n}, _ctx), do: num_box(n)
  defp literal_box({:str, s}, ctx), do: pool(ctx, s)
  defp literal_box({:bool, true}, _ctx), do: "(i32.const 40)"
  defp literal_box({:bool, false}, _ctx), do: "(i32.const 24)"
  defp literal_box({:null}, _ctx), do: "(i32.const 8)"

  defp emit_effect(fields, ctx) do
    {t, ctx} = fresh(ctx)

    lines = ["#{indent(ctx)}(local.set #{t} (call $map_new (i32.const #{length(fields)})))"]

    sets =
      fields
      |> Enum.with_index()
      |> Enum.map(fn {{key, value}, slot} ->
        "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const #{slot}) #{key} #{value})"
      end)

    {lines ++ sets ++ ["#{indent(ctx)}(call $elist_push (local.get #{t}))"], ctx}
  end

  defp emit_expr({:num, n}, ctx), do: {[], num_box(n), ctx}
  defp emit_expr({:bool, true}, ctx), do: {[], "(i32.const 40)", ctx}
  defp emit_expr({:bool, false}, ctx), do: {[], "(i32.const 24)", ctx}
  defp emit_expr({:null}, ctx), do: {[], "(i32.const 8)", ctx}
  defp emit_expr({:str, s}, ctx), do: {[], pool(ctx, s), ctx}
  defp emit_expr({:var, name, _}, ctx), do: {[], "(local.get $L_#{name})", ctx}

  defp emit_expr({:array, items}, ctx) do
    {pres, results, ctx} =
      Enum.reduce(items, {[], [], ctx}, fn expr, {pres, results, ctx} ->
        {pre, res, ctx} = emit_expr(expr, ctx)
        {pres ++ pre, [res | results], ctx}
      end)

    {t, ctx} = fresh(ctx)
    results = Enum.reverse(results)

    setup = ["#{indent(ctx)}(local.set #{t} (call $arr_new (i32.const #{length(results)})))"]

    sets =
      results
      |> Enum.with_index()
      |> Enum.map(fn {res, i} ->
        "#{indent(ctx)}(call $arr_set (local.get #{t}) (i32.const #{i}) #{res})"
      end)

    {pres ++ setup ++ sets, "(local.get #{t})", ctx}
  end

  defp emit_expr({:neg, inner}, ctx) do
    {pre, res, ctx} = emit_expr(inner, ctx)
    {pre, "(call $make_num (f64.neg (call $v_num #{res})))", ctx}
  end

  defp emit_expr({:bin, op, l, r}, ctx) do
    {pre_l, res_l, ctx} = emit_expr(l, ctx)
    {pre_r, res_r, ctx} = emit_expr(r, ctx)
    {pre_l ++ pre_r, bin(op, res_l, res_r), ctx}
  end

  defp emit_expr({:call, name, {:pos, args}, _at}, ctx)
       when name in ["text", "canvas", "col", "row"] do
    emit_view_call(name, args, ctx)
  end

  defp emit_expr({:call, name, {:pos, [arg]}, _at}, ctx) when name in ["show", "len", "floor"] do
    {pre, res, ctx} = emit_expr(arg, ctx)

    body =
      case name do
        "show" -> "(call $v_show #{res})"
        "len" -> "(call $v_len #{res})"
        "floor" -> "(call $make_num (f64.floor (call $v_num #{res})))"
      end

    {pre, body, ctx}
  end

  defp emit_expr({:call, name, {:pos, [a, b]}, _at}, ctx) when name in ["min", "max"] do
    {pre_a, res_a, ctx} = emit_expr(a, ctx)
    {pre_b, res_b, ctx} = emit_expr(b, ctx)
    op = if name == "min", do: "f64.min", else: "f64.max"

    {pre_a ++ pre_b, "(call $make_num (#{op} (call $v_num #{res_a}) (call $v_num #{res_b})))",
     ctx}
  end

  defp emit_view_call("text", [arg], ctx) do
    {pre, res, ctx} = emit_expr(arg, ctx)
    {t, ctx} = fresh(ctx)

    lines = [
      "#{indent(ctx)}(local.set #{t} (call $map_new (i32.const 2)))",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 0) #{pool(ctx, "t")} #{pool(ctx, "text")})",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 1) #{pool(ctx, "s")} #{res})"
    ]

    {pre ++ lines, "(local.get #{t})", ctx}
  end

  defp emit_view_call("canvas", [w, h], ctx) do
    {pre_w, res_w, ctx} = emit_expr(w, ctx)
    {pre_h, res_h, ctx} = emit_expr(h, ctx)
    {t, ctx} = fresh(ctx)

    lines = [
      "#{indent(ctx)}(local.set #{t} (call $map_new (i32.const 3)))",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 0) #{pool(ctx, "t")} #{pool(ctx, "canvas")})",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 1) #{pool(ctx, "w")} #{res_w})",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 2) #{pool(ctx, "h")} #{res_h})"
    ]

    {pre_w ++ pre_h ++ lines, "(local.get #{t})", ctx}
  end

  defp emit_view_call(name, args, ctx) do
    {pres, results, ctx} =
      Enum.reduce(args, {[], [], ctx}, fn arg, {pres, results, ctx} ->
        {pre, res, ctx} = emit_expr(arg, ctx)
        {pres ++ pre, [res | results], ctx}
      end)

    results = Enum.reverse(results)
    {kids, ctx} = fresh(ctx)
    {t, ctx} = fresh(ctx)

    kid_lines =
      [
        "#{indent(ctx)}(local.set #{kids} (call $arr_new (i32.const #{length(results)})))"
      ] ++
        (results
         |> Enum.with_index()
         |> Enum.map(fn {res, i} ->
           "#{indent(ctx)}(call $arr_set (local.get #{kids}) (i32.const #{i}) #{res})"
         end))

    map_lines = [
      "#{indent(ctx)}(local.set #{t} (call $map_new (i32.const 2)))",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 0) #{pool(ctx, "t")} #{pool(ctx, name)})",
      "#{indent(ctx)}(call $map_set (local.get #{t}) (i32.const 1) #{pool(ctx, "kids")} (local.get #{kids}))"
    ]

    {pres ++ kid_lines ++ map_lines, "(local.get #{t})", ctx}
  end

  defp bin(:add, l, r), do: "(call $v_add #{l} #{r})"
  defp bin(:sub, l, r), do: "(call $make_num (f64.sub (call $v_num #{l}) (call $v_num #{r})))"
  defp bin(:mul, l, r), do: "(call $make_num (f64.mul (call $v_num #{l}) (call $v_num #{r})))"
  defp bin(:div, l, r), do: "(call $make_num (f64.div (call $v_num #{l}) (call $v_num #{r})))"

  defp bin(:rem, l, r),
    do:
      "(call $make_num (f64.sub (call $v_num #{l}) (f64.mul (call $v_num #{r}) (f64.trunc (f64.div (call $v_num #{l}) (call $v_num #{r}))))))"

  defp bin(:eq, l, r), do: "(call $make_bool (call $v_eq #{l} #{r}))"
  defp bin(:ne, l, r), do: "(call $make_bool (i32.eqz (call $v_eq #{l} #{r})))"
  defp bin(:lt, l, r), do: "(call $v_lt #{l} #{r})"
  defp bin(:le, l, r), do: "(call $v_le #{l} #{r})"
  defp bin(:gt, l, r), do: "(call $v_lt #{r} #{l})"
  defp bin(:ge, l, r), do: "(call $v_le #{r} #{l})"

  defp bin(:and, l, r),
    do: "(call $make_bool (i32.and (call $truthy #{l}) (call $truthy #{r})))"

  defp bin(:or, l, r),
    do: "(call $make_bool (i32.or (call $truthy #{l}) (call $truthy #{r})))"

  defp num_box(n) do
    case f64_text(n) do
      {:bits, bits} -> "(call $make_num (f64.reinterpret_i64 (i64.const #{bits})))"
      {:text, text} -> "(call $make_num (f64.const #{text}))"
    end
  end

  defp f64_text(n) do
    text = :erlang.float_to_binary(n, [:short])

    if String.contains?(text, ["e", "E"]) do
      <<bits::signed-64>> = <<n::float-64>>
      {:bits, bits}
    else
      {:text, text}
    end
  end

  defp fresh(ctx), do: {"$t#{ctx.temp}", %{ctx | temp: ctx.temp + 1}}

  # A statement context carries the plan; dispatch carries the plan itself.
  defp pool(%{plan: %{pool: pool}}, str), do: "(i32.const #{Map.fetch!(pool, str)})"
  defp pool(%{pool: pool}, str), do: "(i32.const #{Map.fetch!(pool, str)})"

  # -------------------------------------------------------------- dispatch

  defp emit_handle(plan) do
    dispatch = plan.handlers |> Enum.map(&dispatch_line(&1, plan)) |> List.flatten()

    Enum.join(
      [
        "  (func (export \"handle\") (param $in i32) (param $len i32) (result i32)",
        "    (local $dm i32) (local $dmt i32) (local $dok i32)",
        "    (global.set $vp (i32.and (i32.add (i32.add (local.get $in) (local.get $len)) (i32.const 7)) (i32.const -8)))",
        "    (global.set $ec (i32.const 4096))",
        "    (global.set $ep (i32.const 0))",
        "    (global.set $err (i32.const 0))",
        "    (global.set $sc (i32.const 0))",
        "    (global.set $scb (i32.const 0))",
        "    (global.set $scc (i32.const 0))",
        "    (global.set $dp (local.get $in))",
        "    (global.set $de (i32.add (local.get $in) (local.get $len)))",
        "    (local.set $dm (call $cbor_val (i32.const 0)))",
        "    (local.set $dmt (call $v_field (local.get $dm) #{pool(plan, "msg")}))"
        | dispatch
      ] ++ ["    (call $finish)", "  )"],
      "\n"
    )
  end

  defp dispatch_line(%{kind: :init}, plan) do
    [
      "    (if (call $v_text_eq (local.get $dmt) #{pool(plan, "init")})",
      "      (then (call $h_init)))"
    ]
  end

  defp dispatch_line(%{kind: :tick}, plan) do
    [
      "    (if (call $v_text_eq (local.get $dmt) #{pool(plan, "tick")})",
      "      (then (call $h_tick (call $v_field (local.get $dm) #{pool(plan, "t")}))))"
    ]
  end

  defp dispatch_line(%{kind: :ui}, plan) do
    [
      "    (if (call $v_text_eq (local.get $dmt) #{pool(plan, "ui")})",
      "      (then (call $h_ui (call $v_field (local.get $dm) #{pool(plan, "event")}))))"
    ]
  end

  defp dispatch_line(%{kind: :err}, plan) do
    [
      "    (if (call $v_text_eq (local.get $dmt) #{pool(plan, "err")})",
      "      (then (call $h_err (call $v_field (local.get $dm) #{pool(plan, "error")}))))"
    ]
  end

  defp dispatch_line(%{kind: :data, ref: ref}, plan) do
    [
      "    (if (i32.and (call $v_text_eq (local.get $dmt) #{pool(plan, "data")})",
      "      (call $v_num_eq (call $v_field (local.get $dm) #{pool(plan, "ref")}) (f64.const #{ref})))",
      "      (then",
      "        (local.set $dok (call $v_field (local.get $dm) #{pool(plan, "ok")}))",
      "        (if (i32.eq (call $v_tag (local.get $dok)) (i32.const 5))",
      "          (then",
      "            (global.set $dp (i32.add (local.get $dok) (i32.const 8)))",
      "            (global.set $de (i32.add (i32.add (local.get $dok) (i32.const 8)) (i32.load offset=4 (local.get $dok))))",
      "            (call $h_data_#{ref} (call $cbor_val (i32.const 0)))))))"
    ]
  end
end
