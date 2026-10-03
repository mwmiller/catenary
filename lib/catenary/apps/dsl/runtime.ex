defmodule Catenary.Apps.DSL.Runtime do
  @moduledoc """
  The runtime every DSL-generated module links in: one hand-written WAT
  fragment the compiler splices into the modules it emits.

  It implements the two halves a generated program needs at run time:

    * a **value arena** — every DSL value is an 8-byte-aligned box in
      linear memory, tagged 0..7 (null, false, true, number, text, bytes,
      array, map). Boxes are born here and die with the turn, because
      `handle` resets the arena cursor on entry;
    * the **ABI ceremony** — CBOR in (`cbor_val`, bounds-checked, never
      trapping, refusing what the host never sends), CBOR out (`enc_val`
      into the effect buffer), and the effect list itself: each statement
      pushes one effect box onto a list growing down from 0x1000, and
      `finish` wraps the whole list in one CBOR array, writes its length
      to address 0 and returns its address — the entire wasm half of the
      ABI in one place.

  The addresses below are a contract with the compiler, which emits its
  constant pool above them and reads them back as fixed constants:

      8      null box        56     the empty effect array (one 0x80 byte)
      24     false box       64     the text "true"  (show of a boolean)
      40     true box        80     the text "false"
      96     the text "null" 112    pool base — the compiler starts here

  Layout inside a turn: the host's message sits at INPUT_BASE (0x1000) and
  upward; the effect-pointer list grows down from INPUT_BASE toward the
  pool; the value arena grows up from the end of the message; the encoded
  effect array grows up from the arena once every statement has run — the
  only time the two ever meet — and `memory.grow` keeps them apart.

  Input is what the host's own encoder produces: definite-length CBOR,
  single bytes, no nesting below 64. Anything else reads as null and a
  refused turn rather than as a trap.
  """

  @doc "Addresses the compiler treats as constants. See the moduledoc."
  def constants do
    %{
      null: 8,
      false_box: 24,
      true_box: 40,
      empty: 56,
      text_true: 64,
      text_false: 80,
      text_null: 96,
      pool_base: 112,
      elist_top: 0x1000,
      input_base: 0x1000
    }
  end

  @doc "The runtime as WAT — globals and functions, no module wrapper."
  @spec source() :: String.t()
  def source do
    """
      (global $vp (mut i32) (i32.const 0))
      (global $ec (mut i32) (i32.const 4096))
      (global $ep (mut i32) (i32.const 0))
      (global $err (mut i32) (i32.const 0))
      (global $sc (mut i32) (i32.const 0))
      (global $scb (mut i32) (i32.const 0))
      (global $scc (mut i32) (i32.const 0))
      (global $dp (mut i32) (i32.const 0))
      (global $de (mut i32) (i32.const 0))

      ;; ----------------------------------------------------------------
      ;; arena
      ;; ----------------------------------------------------------------

      (func $need_v (param $n i32)
        (local $end i32)
        (local.set $end (i32.mul (memory.size) (i32.const 65536)))
        (if (i32.gt_u (i32.add (global.get $vp) (local.get $n)) (local.get $end))
          (then
            (drop (memory.grow
              (i32.div_u
                (i32.add
                  (i32.sub (i32.add (global.get $vp) (local.get $n)) (local.get $end))
                  (i32.const 65535))
                (i32.const 65536)))))))

      (func $need_e (param $n i32)
        (local $end i32)
        (local.set $end (i32.mul (memory.size) (i32.const 65536)))
        (if (i32.gt_u (i32.add (global.get $ep) (local.get $n)) (local.get $end))
          (then
            (drop (memory.grow
              (i32.div_u
                (i32.add
                  (i32.sub (i32.add (global.get $ep) (local.get $n)) (local.get $end))
                  (i32.const 65535))
                (i32.const 65536)))))))

      (func $alloc (param $n i32) (result i32)
        (local $size i32)
        (local $p i32)
        (local.set $size (i32.and (i32.add (local.get $n) (i32.const 7)) (i32.const -8)))
        (call $need_v (local.get $size))
        (local.set $p (global.get $vp))
        (global.set $vp (i32.add (local.get $p) (local.get $size)))
        (local.get $p))

      (func $make_num (param $f f64) (result i32)
        (local $p i32)
        (local.set $p (call $alloc (i32.const 16)))
        (i32.store8 (local.get $p) (i32.const 3))
        (f64.store offset=8 (local.get $p) (local.get $f))
        (local.get $p))

      (func $make_bool (param $b i32) (result i32)
        (if (result i32) (local.get $b)
          (then (i32.const 40))
          (else (i32.const 24))))

      (func $make_blob (param $tag i32) (param $src i32) (param $len i32) (result i32)
        (local $b i32)
        (local.set $b (call $alloc (i32.add (i32.const 8) (local.get $len))))
        (i32.store8 (local.get $b) (local.get $tag))
        (i32.store offset=4 (local.get $b) (local.get $len))
        (memory.copy (i32.add (local.get $b) (i32.const 8)) (local.get $src) (local.get $len))
        (local.get $b))

      (func $make_text (param $src i32) (param $len i32) (result i32)
        (call $make_blob (i32.const 4) (local.get $src) (local.get $len)))

      (func $arr_new (param $n i32) (result i32)
        (local $a i32)
        (local.set $a (call $alloc (i32.add (i32.const 8) (i32.mul (local.get $n) (i32.const 4)))))
        (i32.store8 (local.get $a) (i32.const 6))
        (i32.store offset=4 (local.get $a) (local.get $n))
        (local.get $a))

      (func $arr_set (param $a i32) (param $i i32) (param $v i32)
        (if (i32.lt_u (local.get $i) (i32.load offset=4 (local.get $a)))
          (then
            (i32.store
              (i32.add (i32.add (local.get $a) (i32.const 8)) (i32.mul (local.get $i) (i32.const 4)))
              (local.get $v)))))

      (func $map_new (param $n i32) (result i32)
        (local $m i32)
        (local.set $m (call $alloc (i32.add (i32.const 8) (i32.mul (local.get $n) (i32.const 8)))))
        (i32.store8 (local.get $m) (i32.const 7))
        (i32.store offset=4 (local.get $m) (local.get $n))
        (local.get $m))

      (func $map_set (param $m i32) (param $i i32) (param $k i32) (param $v i32)
        (if (i32.lt_u (local.get $i) (i32.load offset=4 (local.get $m)))
          (then
            (i32.store
              (i32.add (i32.add (local.get $m) (i32.const 8)) (i32.mul (local.get $i) (i32.const 8)))
              (local.get $k))
            (i32.store
              (i32.add (i32.add (local.get $m) (i32.const 12)) (i32.mul (local.get $i) (i32.const 8)))
              (local.get $v)))))

      ;; One statement, one push. The list grows down from 0x1000 so it can
      ;; never meet the host's message, which only grows upward from there.
      ;; The compiler has already checked that the pool below cannot reach
      ;; it; this guard is belt.
      (func $elist_push (param $v i32)
        (if (i32.gt_u (global.get $ec) (i32.const 112))
          (then
            (global.set $ec (i32.sub (global.get $ec) (i32.const 4)))
            (i32.store (global.get $ec) (local.get $v)))))

      ;; ----------------------------------------------------------------
      ;; value operations
      ;; ----------------------------------------------------------------

      (func $v_tag (param $v i32) (result i32)
        (i32.load8_u (local.get $v)))

      (func $v_num (param $v i32) (result f64)
        (if (result f64) (i32.eq (call $v_tag (local.get $v)) (i32.const 3))
          (then (f64.load offset=8 (local.get $v)))
          (else (f64.const nan))))

      (func $truthy (param $v i32) (result i32)
        (local $tag i32)
        (local.set $tag (call $v_tag (local.get $v)))
        (if (result i32) (i32.eq (local.get $tag) (i32.const 0))
          (then (i32.const 0))
          (else
            (if (result i32) (i32.eq (local.get $tag) (i32.const 1))
              (then (i32.const 0))
              (else
                (if (result i32) (i32.eq (local.get $tag) (i32.const 2))
                  (then (i32.const 1))
                  (else
                    (if (result i32) (i32.eq (local.get $tag) (i32.const 3))
                      (then
                        (i32.and
                          (f64.ne (f64.load offset=8 (local.get $v)) (f64.const 0.0))
                          (f64.eq (f64.load offset=8 (local.get $v)) (f64.load offset=8 (local.get $v)))))
                      (else
                        (if (result i32)
                          (i32.or
                            (i32.eq (local.get $tag) (i32.const 4))
                            (i32.eq (local.get $tag) (i32.const 5)))
                          (then (i32.gt_u (i32.load offset=4 (local.get $v)) (i32.const 0)))
                          (else (i32.const 1))))))))))))

      ;; Byte-wise three-way compare — there is no memory.compare in wasm,
      ;; and the loop is also how a shorter prefix sorts first.
      (func $bcmp (param $a i32) (param $b i32) (param $n i32) (result i32)
        (local $i i32)
        (local $x i32)
        (local $y i32)
        (block $done
          (loop $next
            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
            (local.set $x (i32.load8_u (i32.add (local.get $a) (local.get $i))))
            (local.set $y (i32.load8_u (i32.add (local.get $b) (local.get $i))))
            (br_if $done (i32.ne (local.get $x) (local.get $y)))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $next)))
        (if (result i32) (i32.ge_u (local.get $i) (local.get $n))
          (then (i32.const 0))
          (else
            (if (result i32) (i32.lt_u (local.get $x) (local.get $y))
              (then (i32.const -1))
              (else (i32.const 1))))))

      (func $v_text_eq (param $a i32) (param $b i32) (result i32)
        (local $la i32)
        (if (result i32)
          (i32.and
            (i32.eq (call $v_tag (local.get $a)) (i32.const 4))
            (i32.eq (call $v_tag (local.get $b)) (i32.const 4)))
          (then
            (local.set $la (i32.load offset=4 (local.get $a)))
            (i32.and
              (i32.eq (local.get $la) (i32.load offset=4 (local.get $b)))
              (i32.eq
                (call $bcmp
                  (i32.add (local.get $a) (i32.const 8))
                  (i32.add (local.get $b) (i32.const 8))
                  (local.get $la))
                (i32.const 0))))
          (else (i32.const 0))))

      (func $v_bytes_eq (param $a i32) (param $b i32) (result i32)
        (i32.and
          (i32.eq
            (i32.load offset=4 (local.get $a))
            (i32.load offset=4 (local.get $b)))
          (i32.eq
            (call $bcmp
              (i32.add (local.get $a) (i32.const 8))
              (i32.add (local.get $b) (i32.const 8))
              (i32.load offset=4 (local.get $a)))
            (i32.const 0))))

      (func $v_num_eq (param $a i32) (param $f f64) (result i32)
        (i32.and
          (i32.eq (call $v_tag (local.get $a)) (i32.const 3))
          (f64.eq (f64.load offset=8 (local.get $a)) (local.get $f))))

      ;; Keys match by value, never by address: a field name from the pool
      ;; and the same name decoded from the message are different boxes.
      (func $key_eq (param $a i32) (param $b i32) (result i32)
        (if (result i32)
          (i32.and
            (i32.eq (call $v_tag (local.get $a)) (i32.const 3))
            (i32.eq (call $v_tag (local.get $b)) (i32.const 3)))
          (then (f64.eq (f64.load offset=8 (local.get $a)) (f64.load offset=8 (local.get $b))))
          (else (call $v_text_eq (local.get $a) (local.get $b)))))

      ;; 0 means "no such key" — address 0 is the length slot, never a box,
      ;; so it cannot be confused with a found value, not even a null one.
      (func $find_key (param $m i32) (param $k i32) (result i32)
        (local $found i32)
        (local $n i32)
        (local $i i32)
        (local $e i32)
        (if (i32.eq (call $v_tag (local.get $m)) (i32.const 7))
          (then
            (local.set $n (i32.load offset=4 (local.get $m)))
            (block $out
              (loop $each
                (br_if $out (i32.ge_u (local.get $i) (local.get $n)))
                (local.set $e
                  (i32.add (i32.add (local.get $m) (i32.const 8)) (i32.mul (local.get $i) (i32.const 8))))
                (if (call $key_eq (i32.load (local.get $e)) (local.get $k))
                  (then
                    (local.set $found (i32.load offset=4 (local.get $e)))
                    (br $out)))
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $each)))))
        (local.get $found))

      (func $v_field (param $m i32) (param $k i32) (result i32)
        (local $found i32)
        (local.set $found (call $find_key (local.get $m) (local.get $k)))
        (if (result i32) (i32.eqz (local.get $found))
          (then (i32.const 8))
          (else (local.get $found))))

      (func $v_index (param $a i32) (param $i i32) (result i32)
        (local $n f64)
        (if (result i32) (i32.ne (call $v_tag (local.get $a)) (i32.const 6))
          (then (i32.const 8))
          (else
            (local.set $n (call $v_num (local.get $i)))
            (if (result i32)
              (i32.and
                (i32.and
                  (f64.eq (local.get $n) (f64.floor (local.get $n)))
                  (f64.ge (local.get $n) (f64.const 0.0)))
                (f64.lt (local.get $n) (f64.const 4294967296.0)))
              (then
                (if (result i32)
                  (i32.lt_u
                    (i32.trunc_sat_f64_u (local.get $n))
                    (i32.load offset=4 (local.get $a)))
                  (then
                    (i32.load
                      (i32.add (i32.add (local.get $a) (i32.const 8))
                        (i32.mul (i32.trunc_sat_f64_u (local.get $n)) (i32.const 4)))))
                  (else (i32.const 8))))
              (else (i32.const 8))))))

      ;; Structural equality. A value was already depth-capped when it was
      ;; decoded, so recursion bottoms out on data, not on stack.
      (func $v_eq (param $a i32) (param $b i32) (result i32)
        (local $tag i32)
        (local $n i32)
        (local $i i32)
        (local $e i32)
        (local $other i32)
        (local $same i32)
        (local.set $tag (call $v_tag (local.get $a)))
        (if (result i32) (i32.ne (local.get $tag) (call $v_tag (local.get $b)))
          (then (i32.const 0))
          (else
            (if (result i32) (i32.eq (local.get $tag) (i32.const 0))
              (then (i32.const 1))
              (else
                (if (result i32)
                  (i32.or
                    (i32.eq (local.get $tag) (i32.const 1))
                    (i32.eq (local.get $tag) (i32.const 2)))
                  (then (i32.const 1))
                  (else
                    (if (result i32) (i32.eq (local.get $tag) (i32.const 3))
                      (then (f64.eq (f64.load offset=8 (local.get $a)) (f64.load offset=8 (local.get $b))))
                      (else
                        (if (result i32) (i32.eq (local.get $tag) (i32.const 4))
                          (then (call $v_text_eq (local.get $a) (local.get $b)))
                          (else
                            (if (result i32) (i32.eq (local.get $tag) (i32.const 5))
                              (then (call $v_bytes_eq (local.get $a) (local.get $b)))
                              (else
                                (if (result i32) (i32.eq (local.get $tag) (i32.const 6))
                              (then
                                (local.set $n (i32.load offset=4 (local.get $a)))
                                (local.set $same (i32.const 1))
                                (if (i32.ne (local.get $n) (i32.load offset=4 (local.get $b)))
                                  (then (local.set $same (i32.const 0))))
                                (local.set $i (i32.const 0))
                                (block $done
                                  (loop $each
                                    (br_if $done (i32.eqz (local.get $same)))
                                    (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                                    (if (i32.eqz
                                          (call $v_eq
                                            (i32.load (i32.add (i32.add (local.get $a) (i32.const 8)) (i32.mul (local.get $i) (i32.const 4))))
                                            (i32.load (i32.add (i32.add (local.get $b) (i32.const 8)) (i32.mul (local.get $i) (i32.const 4))))))
                                      (then (local.set $same (i32.const 0))))
                                    (local.set $i (i32.add (local.get $i) (i32.const 1)))
                                    (br $each)))
                                (local.get $same))
                              (else
                                ;; map: same count, every entry of a found in b
                                (local.set $n (i32.load offset=4 (local.get $a)))
                                (local.set $same (i32.const 1))
                                (if (i32.ne (local.get $n) (i32.load offset=4 (local.get $b)))
                                  (then (local.set $same (i32.const 0))))
                                (local.set $i (i32.const 0))
                                (block $done
                                  (loop $each
                                    (br_if $done (i32.eqz (local.get $same)))
                                    (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                                    (local.set $e
                                      (i32.add (i32.add (local.get $a) (i32.const 8)) (i32.mul (local.get $i) (i32.const 8))))
                                    (local.set $other (call $find_key (local.get $b) (i32.load (local.get $e))))
                                    (if (i32.eqz (local.get $other))
                                      (then (local.set $same (i32.const 0)))
                                      (else
                                        (if (i32.eqz
                                              (call $v_eq (i32.load offset=4 (local.get $e)) (local.get $other)))
                                          (then (local.set $same (i32.const 0))))))
                                    (local.set $i (i32.add (local.get $i) (i32.const 1)))
                                    (br $each)))
                                (local.get $same))))))))))))))))

      ;; Ordering compares like with like: two numbers numerically, two
      ;; texts byte-wise with the shorter prefix first. Anything else has
      ;; no order and compares false, rather than coercing.
      (func $v_lt (param $a i32) (param $b i32) (result i32)
        (local $cmp i32)
        (if (result i32)
          (i32.and
            (i32.eq (call $v_tag (local.get $a)) (i32.const 3))
            (i32.eq (call $v_tag (local.get $b)) (i32.const 3)))
          (then (call $make_bool
            (f64.lt (f64.load offset=8 (local.get $a)) (f64.load offset=8 (local.get $b)))))
          (else
            (if (result i32)
              (i32.and
                (i32.eq (call $v_tag (local.get $a)) (i32.const 4))
                (i32.eq (call $v_tag (local.get $b)) (i32.const 4)))
              (then
                (local.set $cmp
                  (call $bcmp
                    (i32.add (local.get $a) (i32.const 8))
                    (i32.add (local.get $b) (i32.const 8))
                    (select (i32.load offset=4 (local.get $a)) (i32.load offset=4 (local.get $b))
                      (i32.lt_u (i32.load offset=4 (local.get $a)) (i32.load offset=4 (local.get $b))))))
                (call $make_bool
                  (if (result i32) (i32.lt_s (local.get $cmp) (i32.const 0))
                    (then (i32.const 1))
                    (else
                      (i32.and
                        (i32.eq (local.get $cmp) (i32.const 0))
                        (i32.lt_u (i32.load offset=4 (local.get $a)) (i32.load offset=4 (local.get $b))))))))
              (else (i32.const 24))))))

      (func $v_le (param $a i32) (param $b i32) (result i32)
        (local $cmp i32)
        (if (result i32)
          (i32.and
            (i32.eq (call $v_tag (local.get $a)) (i32.const 3))
            (i32.eq (call $v_tag (local.get $b)) (i32.const 3)))
          (then (call $make_bool
            (f64.le (f64.load offset=8 (local.get $a)) (f64.load offset=8 (local.get $b)))))
          (else
            (if (result i32)
              (i32.and
                (i32.eq (call $v_tag (local.get $a)) (i32.const 4))
                (i32.eq (call $v_tag (local.get $b)) (i32.const 4)))
              (then
                (local.set $cmp
                  (call $bcmp
                    (i32.add (local.get $a) (i32.const 8))
                    (i32.add (local.get $b) (i32.const 8))
                    (select (i32.load offset=4 (local.get $a)) (i32.load offset=4 (local.get $b))
                      (i32.lt_u (i32.load offset=4 (local.get $a)) (i32.load offset=4 (local.get $b))))))
                (call $make_bool
                  (if (result i32) (i32.lt_s (local.get $cmp) (i32.const 0))
                    (then (i32.const 1))
                    (else
                      (i32.and
                        (i32.eq (local.get $cmp) (i32.const 0))
                        (i32.le_u (i32.load offset=4 (local.get $a)) (i32.load offset=4 (local.get $b))))))))
              (else (i32.const 24))))))

      ;; `+` is the one operator with a second meaning: two numbers add,
      ;; anything touching a text concatenates. Everything else is a
      ;; number, and a value that is not one arrives as NaN rather than as
      ;; a silent zero, so a bad operand shows up in the print log.
      (func $v_add (param $a i32) (param $b i32) (result i32)
        (if (result i32)
          (i32.or
            (i32.eq (call $v_tag (local.get $a)) (i32.const 4))
            (i32.eq (call $v_tag (local.get $b)) (i32.const 4)))
          (then (call $concat (call $v_show (local.get $a)) (call $v_show (local.get $b))))
          (else (call $make_num
            (f64.add (call $v_num (local.get $a)) (call $v_num (local.get $b)))))))

      (func $concat (param $a i32) (param $b i32) (result i32)
        (local $la i32)
        (local $lb i32)
        (local $out i32)
        (local.set $la (i32.load offset=4 (local.get $a)))
        (local.set $lb (i32.load offset=4 (local.get $b)))
        (local.set $out (call $alloc (i32.add (i32.const 8) (i32.add (local.get $la) (local.get $lb)))))
        (i32.store8 (local.get $out) (i32.const 4))
        (i32.store offset=4 (local.get $out) (i32.add (local.get $la) (local.get $lb)))
        (memory.copy (i32.add (local.get $out) (i32.const 8))
          (i32.add (local.get $a) (i32.const 8)) (local.get $la))
        (memory.copy (i32.add (i32.add (local.get $out) (i32.const 8)) (local.get $la))
          (i32.add (local.get $b) (i32.const 8)) (local.get $lb))
        (local.get $out))

      (func $v_len (param $v i32) (result i32)
        (local $tag i32)
        (local.set $tag (call $v_tag (local.get $v)))
        (if (result i32)
          (i32.or
            (i32.or (i32.eq (local.get $tag) (i32.const 4)) (i32.eq (local.get $tag) (i32.const 5)))
            (i32.or (i32.eq (local.get $tag) (i32.const 6)) (i32.eq (local.get $tag) (i32.const 7))))
          (then (call $make_num (f64.convert_i32_u (i32.load offset=4 (local.get $v)))))
          (else (call $make_num (f64.const nan)))))

      ;; ----------------------------------------------------------------
      ;; show — text passes through, everything else walks into a bounded
      ;; scratch buffer so a hostile structure cannot print forever.
      ;; ----------------------------------------------------------------

      (func $s_char (param $c i32)
        (if (i32.eqz (global.get $scc))
          (then
            (if (i32.lt_u (i32.sub (global.get $sc) (global.get $scb)) (i32.const 3000))
              (then
                (i32.store8 (global.get $sc) (local.get $c))
                (global.set $sc (i32.add (global.get $sc) (i32.const 1))))
              (else (global.set $scc (i32.const 1)))))))

      (func $s_str (param $p i32) (param $n i32)
        (local $i i32)
        (block $done
          (loop $next
            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
            (br_if $done (global.get $scc))
            (call $s_char (i32.load8_u (i32.add (local.get $p) (local.get $i))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $next))))

      ;; Digits by peeling with floor, then reversing the run written.
      (func $s_int (param $n f64)
        (local $start i32)
        (local $q f64)
        (local $d i32)
        (local $mid i32)
        (local $i i32)
        (local $t i32)
        (local.set $start (global.get $sc))
        (if (f64.eq (local.get $n) (f64.const 0.0))
          (then (call $s_char (i32.const 48)))
          (else
            (block $done
              (loop $next
                (br_if $done (f64.lt (local.get $n) (f64.const 1.0)))
                (br_if $done (global.get $scc))
                (local.set $q (f64.floor (f64.div (local.get $n) (f64.const 10.0))))
                (local.set $d (i32.trunc_sat_f64_s
                  (f64.sub (local.get $n) (f64.mul (local.get $q) (f64.const 10.0)))))
                (call $s_char (i32.add (local.get $d) (i32.const 48)))
                (local.set $n (local.get $q))
                (br $next)))
            (local.set $mid (i32.div_u (i32.sub (global.get $sc) (local.get $start)) (i32.const 2)))
            (local.set $i (i32.const 0))
            (block $done
              (loop $next
                (br_if $done (i32.ge_u (local.get $i) (local.get $mid)))
                (local.set $t (i32.load8_u (i32.add (local.get $start) (local.get $i))))
                (i32.store8 (i32.add (local.get $start) (local.get $i))
                  (i32.load8_u (i32.sub (i32.sub (global.get $sc) (i32.const 1)) (local.get $i))))
                (i32.store8 (i32.sub (i32.sub (global.get $sc) (i32.const 1)) (local.get $i)) (local.get $t))
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $next))))))

      ;; 15 fraction digits, then trimmed — a deliberate divergence from
      ;; JavaScript's shortest round-trip form, kept simple.
      (func $s_num (param $n f64)
        (local $int f64)
        (local $frac f64)
        (local $dot i32)
        (local $i i32)
        (local $d i32)
        (if (f64.ne (local.get $n) (local.get $n))
          (then
            (call $s_char (i32.const 110))
            (call $s_char (i32.const 97))
            (call $s_char (i32.const 110))
            (return)))
        (if (f64.eq (f64.abs (local.get $n)) (f64.const inf))
          (then
            (if (f64.lt (local.get $n) (f64.const 0.0))
              (then (call $s_char (i32.const 45))))
            (call $s_char (i32.const 105))
            (call $s_char (i32.const 110))
            (call $s_char (i32.const 102))
            (return)))
        (if (f64.lt (local.get $n) (f64.const 0.0))
          (then
            (call $s_char (i32.const 45))
            (local.set $n (f64.neg (local.get $n)))))
        (if (f64.eq (local.get $n) (f64.floor (local.get $n)))
          (then (call $s_int (local.get $n)))
          (else
            (local.set $int (f64.floor (local.get $n)))
            (local.set $frac (f64.sub (local.get $n) (local.get $int)))
            (call $s_int (local.get $int))
            (call $s_char (i32.const 46))
            (local.set $dot (global.get $sc))
            (local.set $i (i32.const 0))
            (block $done
              (loop $next
                (br_if $done (i32.ge_u (local.get $i) (i32.const 15)))
                (local.set $frac (f64.mul (local.get $frac) (f64.const 10.0)))
                (local.set $d (i32.trunc_sat_f64_s (f64.floor (local.get $frac))))
                (call $s_char (i32.add (local.get $d) (i32.const 48)))
                (local.set $frac (f64.sub (local.get $frac) (f64.convert_i32_s (local.get $d))))
                (local.set $i (i32.add (local.get $i) (i32.const 1)))
                (br $next)))
            ;; trim trailing zeros, then a point left with nothing after it
            (block $done
              (loop $next
                (br_if $done (i32.le_u (global.get $sc) (local.get $dot)))
                (br_if $done
                  (i32.ne (i32.load8_u (i32.sub (global.get $sc) (i32.const 1))) (i32.const 48)))
                (global.set $sc (i32.sub (global.get $sc) (i32.const 1)))
                (br $next)))
            (block $done
              (loop $next
                (br_if $done (i32.le_u (global.get $sc) (local.get $dot)))
                (br_if $done
                  (i32.ne (i32.load8_u (i32.sub (global.get $sc) (i32.const 1))) (i32.const 46)))
                (global.set $sc (i32.sub (global.get $sc) (i32.const 1)))
                (br $next))))))

      (func $s_hex (param $p i32) (param $n i32)
        (local $i i32)
        (local $b i32)
        (block $done
          (loop $next
            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
            (local.set $b (i32.load8_u (i32.add (local.get $p) (local.get $i))))
            (call $s_char
              (i32.add
                (select (i32.const 48) (i32.const 87)
                  (i32.lt_u (i32.shr_u (local.get $b) (i32.const 4)) (i32.const 10)))
                (i32.shr_u (local.get $b) (i32.const 4))))
            (call $s_char
              (i32.add
                (select (i32.const 48) (i32.const 87)
                  (i32.lt_u (i32.and (local.get $b) (i32.const 15)) (i32.const 10)))
                (i32.and (local.get $b) (i32.const 15))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $next))))

      (func $s_val (param $v i32) (param $depth i32)
        (local $tag i32)
        (local $n i32)
        (local $i i32)
        (local $e i32)
        (if (global.get $scc) (then (return)))
        (if (i32.gt_s (local.get $depth) (i32.const 4))
          (then
            (call $s_char (i32.const 46))
            (call $s_char (i32.const 46))
            (call $s_char (i32.const 46))
            (return)))
        (local.set $tag (call $v_tag (local.get $v)))
        (if (i32.eq (local.get $tag) (i32.const 0))
          (then (call $s_str (i32.add (i32.const 96) (i32.const 8)) (i32.const 4)))
          (else
            (if (i32.eq (local.get $tag) (i32.const 1))
              (then (call $s_str (i32.add (i32.const 80) (i32.const 8)) (i32.const 5)))
              (else
                (if (i32.eq (local.get $tag) (i32.const 2))
                  (then (call $s_str (i32.add (i32.const 64) (i32.const 8)) (i32.const 4)))
                  (else
                    (if (i32.eq (local.get $tag) (i32.const 3))
                      (then (call $s_num (f64.load offset=8 (local.get $v))))
                      (else
                        (if (i32.eq (local.get $tag) (i32.const 4))
                          (then
                            (if (i32.gt_s (local.get $depth) (i32.const 0))
                              (then (call $s_char (i32.const 34))))
                            (call $s_str (i32.add (local.get $v) (i32.const 8))
                              (i32.load offset=4 (local.get $v)))
                            (if (i32.gt_s (local.get $depth) (i32.const 0))
                              (then (call $s_char (i32.const 34)))))
                          (else
                            (if (i32.eq (local.get $tag) (i32.const 5))
                              (then
                                (call $s_char (i32.const 48))
                                (call $s_char (i32.const 120))
                                (local.set $n (i32.load offset=4 (local.get $v)))
                                (call $s_hex (i32.add (local.get $v) (i32.const 8))
                                  (select (i32.const 32) (local.get $n)
                                    (i32.gt_u (local.get $n) (i32.const 32))))
                                (if (i32.gt_u (local.get $n) (i32.const 32))
                                  (then
                                    (call $s_char (i32.const 32))
                                    (call $s_char (i32.const 43))
                                    (call $s_int (f64.convert_i32_u (i32.sub (local.get $n) (i32.const 32))))
                                    (call $s_char (i32.const 32))
                                    (call $s_char (i32.const 109))
                                    (call $s_char (i32.const 111))
                                    (call $s_char (i32.const 114))
                                    (call $s_char (i32.const 101))
                                    (call $s_char (i32.const 32))
                                    (call $s_char (i32.const 98))
                                    (call $s_char (i32.const 121))
                                    (call $s_char (i32.const 116))
                                    (call $s_char (i32.const 101))
                                    (call $s_char (i32.const 115)))))
                              (else
                                (if (i32.eq (local.get $tag) (i32.const 6))
                                  (then
                                    (call $s_char (i32.const 91))
                                    (local.set $n (i32.load offset=4 (local.get $v)))
                                    (local.set $i (i32.const 0))
                                    (block $done
                                      (loop $each
                                        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                                        (br_if $done (i32.ge_u (local.get $i) (i32.const 16)))
                                        (if (i32.gt_s (local.get $i) (i32.const 0))
                                          (then (call $s_char (i32.const 44))))
                                        (call $s_val
                                          (i32.load (i32.add (i32.add (local.get $v) (i32.const 8))
                                            (i32.mul (local.get $i) (i32.const 4))))
                                          (i32.add (local.get $depth) (i32.const 1)))
                                        (local.set $i (i32.add (local.get $i) (i32.const 1)))
                                        (br $each)))
                                    (if (i32.ge_u (local.get $n) (i32.const 16))
                                      (then
                                        (call $s_char (i32.const 44))
                                        (call $s_char (i32.const 46))
                                        (call $s_char (i32.const 46))))
                                    (call $s_char (i32.const 93)))
                                  (else
                                    (if (i32.eq (local.get $tag) (i32.const 7))
                                      (then
                                        (call $s_char (i32.const 123))
                                        (local.set $n (i32.load offset=4 (local.get $v)))
                                        (local.set $i (i32.const 0))
                                        (block $done
                                          (loop $each
                                            (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                                            (br_if $done (i32.ge_u (local.get $i) (i32.const 16)))
                                            (if (i32.gt_s (local.get $i) (i32.const 0))
                                              (then (call $s_char (i32.const 44))))
                                            (local.set $e
                                              (i32.add (i32.add (local.get $v) (i32.const 8))
                                                (i32.mul (local.get $i) (i32.const 8))))
                                            (call $s_val (i32.load (local.get $e))
                                              (i32.add (local.get $depth) (i32.const 1)))
                                            (call $s_char (i32.const 58))
                                            (call $s_val (i32.load offset=4 (local.get $e))
                                              (i32.add (local.get $depth) (i32.const 1)))
                                            (local.set $i (i32.add (local.get $i) (i32.const 1)))
                                            (br $each)))
                                        (if (i32.ge_u (local.get $n) (i32.const 16))
                                          (then
                                            (call $s_char (i32.const 44))
                                            (call $s_char (i32.const 46))
                                            (call $s_char (i32.const 46))))
                                        (call $s_char (i32.const 125)))))))))))))))))))

      (func $v_show (param $v i32) (result i32)
        (if (result i32) (i32.eq (call $v_tag (local.get $v)) (i32.const 4))
          (then (local.get $v))
          (else
            (global.set $scb (call $alloc (i32.const 4096)))
            (global.set $sc (global.get $scb))
            (global.set $scc (i32.const 0))
            (call $s_val (local.get $v) (i32.const 0))
            (if (global.get $scc)
              (then
                (i32.store8 (global.get $sc) (i32.const 226))
                (i32.store8 (i32.add (global.get $sc) (i32.const 1)) (i32.const 128))
                (i32.store8 (i32.add (global.get $sc) (i32.const 2)) (i32.const 166))
                (global.set $sc (i32.add (global.get $sc) (i32.const 3)))))
            (call $make_text (global.get $scb) (i32.sub (global.get $sc) (global.get $scb))))))

      ;; ----------------------------------------------------------------
      ;; CBOR out
      ;; ----------------------------------------------------------------

      (func $ebyte (param $b i32)
        (call $need_e (i32.const 1))
        (i32.store8 (global.get $ep) (i32.and (local.get $b) (i32.const 255)))
        (global.set $ep (i32.add (global.get $ep) (i32.const 1))))

      (func $ebe (param $v i64) (param $w i32)
        (local $i i32)
        (block $done
          (loop $next
            (br_if $done (i32.ge_u (local.get $i) (local.get $w)))
            (call $ebyte
              (i32.wrap_i64
                (i64.shr_u (local.get $v)
                  (i64.extend_i32_u (i32.shl (i32.sub (i32.sub (local.get $w) (local.get $i)) (i32.const 1)) (i32.const 3))))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $next))))

      (func $ehead (param $major i32) (param $arg i64)
        (if (i64.lt_u (local.get $arg) (i64.const 24))
          (then (call $ebyte (i32.or (i32.shl (local.get $major) (i32.const 5)) (i32.wrap_i64 (local.get $arg)))))
          (else
            (if (i64.lt_u (local.get $arg) (i64.const 256))
              (then
                (call $ebyte (i32.or (i32.shl (local.get $major) (i32.const 5)) (i32.const 24)))
                (call $ebe (local.get $arg) (i32.const 1)))
              (else
                (if (i64.lt_u (local.get $arg) (i64.const 65536))
                  (then
                    (call $ebyte (i32.or (i32.shl (local.get $major) (i32.const 5)) (i32.const 25)))
                    (call $ebe (local.get $arg) (i32.const 2)))
                  (else
                    (if (i64.lt_u (local.get $arg) (i64.const 4294967296))
                      (then
                        (call $ebyte (i32.or (i32.shl (local.get $major) (i32.const 5)) (i32.const 26)))
                        (call $ebe (local.get $arg) (i32.const 4)))
                      (else
                        (call $ebyte (i32.or (i32.shl (local.get $major) (i32.const 5)) (i32.const 27)))
                        (call $ebe (local.get $arg) (i32.const 8)))))))))))

      (func $enc_val (param $v i32)
        (local $tag i32)
        (local $n i32)
        (local $i i32)
        (local $num f64)
        (local $neg0 i32)
        (local.set $tag (call $v_tag (local.get $v)))
        (if (i32.eq (local.get $tag) (i32.const 0))
          (then (call $ebyte (i32.const 246)))
          (else
            (if (i32.eq (local.get $tag) (i32.const 1))
              (then (call $ebyte (i32.const 244)))
              (else
                (if (i32.eq (local.get $tag) (i32.const 2))
                  (then (call $ebyte (i32.const 245)))
                  (else
                    (if (i32.eq (local.get $tag) (i32.const 3))
                      (then
                        (local.set $num (f64.load offset=8 (local.get $v)))
                        (local.set $neg0
                          (i32.and
                            (f64.eq (local.get $num) (f64.const 0.0))
                            (i32.wrap_i64
                              (i64.shr_u (i64.reinterpret_f64 (local.get $num)) (i64.const 63)))))
                        (if (i32.and
                              (i32.and
                                (f64.eq (local.get $num) (f64.floor (local.get $num)))
                                (f64.le (f64.abs (local.get $num)) (f64.const 9007199254740992.0)))
                              (i32.eqz (local.get $neg0)))
                          (then
                            (if (f64.ge (local.get $num) (f64.const 0.0))
                              (then
                                (call $ehead (i32.const 0) (i64.trunc_sat_f64_s (local.get $num))))
                              (else
                                (call $ehead (i32.const 1)
                                  (i64.trunc_sat_f64_s (f64.sub (f64.const -1.0) (local.get $num)))))))
                          (else
                            (call $ebyte (i32.const 251))
                            (call $ebe (i64.reinterpret_f64 (local.get $num)) (i32.const 8)))))
                      (else
                        (if (i32.eq (local.get $tag) (i32.const 4))
                          (then
                            (local.set $n (i32.load offset=4 (local.get $v)))
                            (call $ehead (i32.const 3) (i64.extend_i32_u (local.get $n)))
                            (call $need_e (local.get $n))
                            (memory.copy (global.get $ep) (i32.add (local.get $v) (i32.const 8)) (local.get $n))
                            (global.set $ep (i32.add (global.get $ep) (local.get $n))))
                          (else
                            (if (i32.eq (local.get $tag) (i32.const 5))
                              (then
                                (local.set $n (i32.load offset=4 (local.get $v)))
                                (call $ehead (i32.const 2) (i64.extend_i32_u (local.get $n)))
                                (call $need_e (local.get $n))
                                (memory.copy (global.get $ep) (i32.add (local.get $v) (i32.const 8)) (local.get $n))
                                (global.set $ep (i32.add (global.get $ep) (local.get $n))))
                              (else
                                (if (i32.eq (local.get $tag) (i32.const 6))
                                  (then
                                    (local.set $n (i32.load offset=4 (local.get $v)))
                                    (call $ehead (i32.const 4) (i64.extend_i32_u (local.get $n)))
                                    (local.set $i (i32.const 0))
                                    (block $done
                                      (loop $each
                                        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                                        (call $enc_val
                                          (i32.load (i32.add (i32.add (local.get $v) (i32.const 8))
                                            (i32.mul (local.get $i) (i32.const 4)))))
                                        (local.set $i (i32.add (local.get $i) (i32.const 1)))
                                        (br $each))))
                                  (else
                                    (local.set $n (i32.load offset=4 (local.get $v)))
                                    (call $ehead (i32.const 5) (i64.extend_i32_u (local.get $n)))
                                    (local.set $i (i32.const 0))
                                    (block $done
                                      (loop $each
                                        (br_if $done (i32.ge_u (local.get $i) (local.get $n)))
                                        (call $enc_val
                                          (i32.load (i32.add (i32.add (local.get $v) (i32.const 8))
                                            (i32.mul (local.get $i) (i32.const 8)))))
                                        (call $enc_val
                                          (i32.load (i32.add (i32.add (local.get $v) (i32.const 12))
                                            (i32.mul (local.get $i) (i32.const 8)))))
                                        (local.set $i (i32.add (local.get $i) (i32.const 1)))
                                        (br $each))))))))))))))))))

      ;; The last act of every handle: the effect list, wrapped and handed
      ;; back the way the ABI expects — length at address 0, bytes where
      ;; the return value points.
      (func $finish (result i32)
        (local $start i32)
        (local $p i32)
        (if (i32.eq (global.get $ec) (i32.const 4096))
          (then
            (i32.store (i32.const 0) (i32.const 1))
            (return (i32.const 56))))
        (global.set $ep (i32.and (i32.add (global.get $vp) (i32.const 7)) (i32.const -8)))
        (local.set $start (global.get $ep))
        (call $ebyte (i32.const 159))
        (local.set $p (i32.const 4092))
        (block $done
          (loop $scan
            (br_if $done (i32.lt_u (local.get $p) (global.get $ec)))
            (call $enc_val (i32.load (local.get $p)))
            (local.set $p (i32.sub (local.get $p) (i32.const 4)))
            (br $scan)))
        (call $ebyte (i32.const 255))
        (i32.store (i32.const 0) (i32.sub (global.get $ep) (local.get $start)))
        (local.get $start))

      ;; ----------------------------------------------------------------
      ;; CBOR in — every read bounds-checked, every failure sets $err and
      ;; yields the null box, so a malformed message costs a turn rather
      ;; than trapping the worker. Input is the host's encoder's work:
      ;; definite lengths, no chunks.
      ;; ----------------------------------------------------------------

      (func $ru8 (result i32)
        (local $b i32)
        (if (i32.ge_u (global.get $dp) (global.get $de))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 0))))
        (local.set $b (i32.load8_u (global.get $dp)))
        (global.set $dp (i32.add (global.get $dp) (i32.const 1)))
        (local.get $b))

      (func $ru_be (param $w i32) (result i64)
        (local $r i64)
        (local $i i32)
        (block $done
          (loop $next
            (br_if $done (i32.ge_u (local.get $i) (local.get $w)))
            (local.set $r
              (i64.or (i64.shl (local.get $r) (i64.const 8)) (i64.extend_i32_u (call $ru8))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $next)))
        (local.get $r))

      ;; ai 0..23 is the argument; 24..27 read 1/2/4/8 bytes; 31 is the
      ;; indefinite marker, which the host never sends — it arrives as -1
      ;; and every caller refuses it.
      (func $arg_of (param $ai i32) (result i64)
        (if (result i64) (i32.lt_u (local.get $ai) (i32.const 24))
          (then (i64.extend_i32_u (local.get $ai)))
          (else
            (if (result i64) (i32.lt_u (local.get $ai) (i32.const 28))
              (then (call $ru_be (i32.shl (i32.const 1) (i32.sub (local.get $ai) (i32.const 24)))))
              (else (i64.const -1))))))

      (func $cbor_val (param $depth i32) (result i32)
        (local $b i32)
        (local $major i32)
        (local $ai i32)
        (if (i32.gt_s (local.get $depth) (i32.const 64))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $b (call $ru8))
        (if (global.get $err) (then (return (i32.const 8))))
        (local.set $major (i32.shr_u (local.get $b) (i32.const 5)))
        (local.set $ai (i32.and (local.get $b) (i32.const 31)))
        (if (i32.eq (local.get $major) (i32.const 0))
          (then (return (call $dec_uint (call $arg_of (local.get $ai))))))
        (if (i32.eq (local.get $major) (i32.const 1))
          (then (return (call $dec_nint (call $arg_of (local.get $ai))))))
        (if (i32.or (i32.eq (local.get $major) (i32.const 2)) (i32.eq (local.get $major) (i32.const 3)))
          (then (return (call $dec_bytes (local.get $major) (call $arg_of (local.get $ai))))))
        (if (i32.eq (local.get $major) (i32.const 4))
          (then (return (call $dec_array (local.get $depth) (call $arg_of (local.get $ai))))))
        (if (i32.eq (local.get $major) (i32.const 5))
          (then (return (call $dec_map (local.get $depth) (call $arg_of (local.get $ai))))))
        (if (i32.eq (local.get $major) (i32.const 6))
          (then (return (call $cbor_val (i32.add (local.get $depth) (i32.const 1))))))
        (return (call $dec_simple (local.get $ai))))

      (func $dec_uint (param $arg i64) (result i32)
        (if (i64.lt_s (local.get $arg) (i64.const 0))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (call $make_num (f64.convert_i64_u (local.get $arg))))

      (func $dec_nint (param $arg i64) (result i32)
        (if (i64.lt_s (local.get $arg) (i64.const 0))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (call $make_num (f64.sub (f64.const -1.0) (f64.convert_i64_u (local.get $arg)))))

      (func $dec_bytes (param $major i32) (param $arg i64) (result i32)
        (local $len i32)
        (local $box i32)
        (if (i64.lt_s (local.get $arg) (i64.const 0))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $len (i32.wrap_i64 (local.get $arg)))
        (if (i32.gt_u (local.get $len) (i32.sub (global.get $de) (global.get $dp)))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $box (call $make_blob
          (if (result i32) (i32.eq (local.get $major) (i32.const 2))
            (then (i32.const 5))
            (else (i32.const 4)))
          (global.get $dp)
          (local.get $len)))
        (global.set $dp (i32.add (global.get $dp) (local.get $len)))
        (local.get $box))

      (func $dec_array (param $depth i32) (param $arg i64) (result i32)
        (local $len i32)
        (local $box i32)
        (local $i i32)
        (if (i64.lt_s (local.get $arg) (i64.const 0))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $len (i32.wrap_i64 (local.get $arg)))
        (if (i32.gt_u (local.get $len) (i32.sub (global.get $de) (global.get $dp)))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $box (call $arr_new (local.get $len)))
        (block $done
          (loop $each
            (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
            (call $arr_set (local.get $box) (local.get $i)
              (call $cbor_val (i32.add (local.get $depth) (i32.const 1))))
            (if (global.get $err) (then (return (i32.const 8))))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $each)))
        (local.get $box))

      (func $dec_map (param $depth i32) (param $arg i64) (result i32)
        (local $len i32)
        (local $box i32)
        (local $i i32)
        (local $k i32)
        (local $v i32)
        (if (i64.lt_s (local.get $arg) (i64.const 0))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $len (i32.wrap_i64 (local.get $arg)))
        (if (i32.gt_u (local.get $len) (i32.div_u (i32.sub (global.get $de) (global.get $dp)) (i32.const 2)))
          (then
            (global.set $err (i32.const 1))
            (return (i32.const 8))))
        (local.set $box (call $map_new (local.get $len)))
        (block $done
          (loop $each
            (br_if $done (i32.ge_u (local.get $i) (local.get $len)))
            (local.set $k (call $cbor_val (i32.add (local.get $depth) (i32.const 1))))
            (if (global.get $err) (then (return (i32.const 8))))
            (local.set $v (call $cbor_val (i32.add (local.get $depth) (i32.const 1))))
            (if (global.get $err) (then (return (i32.const 8))))
            (call $map_set (local.get $box) (local.get $i) (local.get $k) (local.get $v))
            (local.set $i (i32.add (local.get $i) (i32.const 1)))
            (br $each)))
        (local.get $box))

      ;; Major 7: the simple values the host actually sends — false, true,
      ;; null — and the three float widths. The Elixir side sends inf, -inf
      ;; and nan as 16-bit floats, everything else as 64-bit.
      (func $dec_simple (param $ai i32) (result i32)
        (local $out i32)
        (local.set $out (i32.const 8))
        (if (i32.eq (local.get $ai) (i32.const 20)) (then (local.set $out (i32.const 24))))
        (if (i32.eq (local.get $ai) (i32.const 21)) (then (local.set $out (i32.const 40))))
        (if (i32.eq (local.get $ai) (i32.const 22)) (then (local.set $out (i32.const 8))))
        (if (i32.eq (local.get $ai) (i32.const 25)) (then (local.set $out (call $read_f16))))
        (if (i32.eq (local.get $ai) (i32.const 26)) (then (local.set $out (call $read_f32))))
        (if (i32.eq (local.get $ai) (i32.const 27)) (then (local.set $out (call $read_f64))))
        (if (i32.or (i32.eq (local.get $ai) (i32.const 23))
              (i32.or (i32.eq (local.get $ai) (i32.const 24)) (i32.gt_u (local.get $ai) (i32.const 27))))
          (then (global.set $err (i32.const 1))))
        (local.get $out))

      (func $read_f16 (result i32)
        (if (result i32) (i32.gt_u (i32.const 2) (i32.sub (global.get $de) (global.get $dp)))
          (then
            (global.set $err (i32.const 1))
            (i32.const 8))
          (else
            (call $make_num
              (call $f16 (i32.wrap_i64 (call $ru_be (i32.const 2))))))))

      (func $read_f32 (result i32)
        (if (result i32) (i32.gt_u (i32.const 4) (i32.sub (global.get $de) (global.get $dp)))
          (then
            (global.set $err (i32.const 1))
            (i32.const 8))
          (else
            (call $make_num
              (f64.promote_f32
                (f32.reinterpret_i32 (i32.wrap_i64 (call $ru_be (i32.const 4)))))))))

      (func $read_f64 (result i32)
        (if (result i32) (i32.gt_u (i32.const 8) (i32.sub (global.get $de) (global.get $dp)))
          (then
            (global.set $err (i32.const 1))
            (i32.const 8))
          (else
            (call $make_num
              (f64.reinterpret_i64 (call $ru_be (i32.const 8)))))))

      ;; 16-bit IEEE to f64: sign, biased exponent, mantissa. Subnormals
      ;; scale by 2^-24; the scale for normals is built by repeated
      ;; doubling — there is no power instruction to lean on.
      (func $f16 (param $bits i32) (result f64)
        (local $sign f64)
        (local $exp i32)
        (local $mant i32)
        (local $k i32)
        (local $scale f64)
        (local.set $sign (select (f64.const -1.0) (f64.const 1.0)
          (i32.shr_u (local.get $bits) (i32.const 15))))
        (local.set $exp (i32.and (i32.shr_u (local.get $bits) (i32.const 10)) (i32.const 31)))
        (local.set $mant (i32.and (local.get $bits) (i32.const 1023)))
        (if (i32.eq (local.get $exp) (i32.const 31))
          (then
            (if (i32.eqz (local.get $mant))
              (then (return (f64.mul (local.get $sign) (f64.const inf))))
              (else (return (f64.const nan))))))
        (if (i32.eqz (local.get $exp))
          (then
            (return
              (f64.mul (local.get $sign)
                (f64.mul (f64.convert_i32_u (local.get $mant))
                  (f64.const 0.000000059604644775390625))))))
        (local.set $k (i32.sub (local.get $exp) (i32.const 15)))
        (local.set $scale (f64.const 1.0))
        (if (i32.gt_s (local.get $k) (i32.const 0))
          (then
            (block $done
              (loop $next
                (br_if $done (i32.le_s (local.get $k) (i32.const 0)))
                (local.set $scale (f64.mul (local.get $scale) (f64.const 2.0)))
                (local.set $k (i32.sub (local.get $k) (i32.const 1)))
                (br $next))))
          (else
            (block $done
              (loop $next
                (br_if $done (i32.ge_s (local.get $k) (i32.const 0)))
                (local.set $scale (f64.div (local.get $scale) (f64.const 2.0)))
                (local.set $k (i32.add (local.get $k) (i32.const 1)))
                (br $next)))))
        (f64.mul (local.get $sign)
          (f64.mul (local.get $scale)
            (f64.div (f64.convert_i32_u (i32.add (local.get $mant) (i32.const 1024)))
              (f64.const 1024.0)))))
    """
  end

  @doc "The runtime's own data segments: the singleton boxes and phrases."
  @spec data() :: String.t()
  def data do
    """
      (data (i32.const 8) "\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00")
      (data (i32.const 24) "\\01\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00")
      (data (i32.const 40) "\\02\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00\\00")
      (data (i32.const 56) "\\80")
      (data (i32.const 64) "\\04\\00\\00\\00\\04\\00\\00\\00true")
      (data (i32.const 80) "\\04\\00\\00\\00\\05\\00\\00\\00false")
      (data (i32.const 96) "\\04\\00\\00\\00\\04\\00\\00\\00null")
    """
  end
end
