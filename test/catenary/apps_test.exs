defmodule Catenary.AppsTest do
  use ExUnit.Case, async: true

  doctest Catenary.Apps

  @pk "ExampleAuthor1"
  @other_pk "ExampleAuthor2"
  @channel Catenary.Apps.app_base(@pk, "example-app")

  describe "golden vectors" do
    # These pin the `SHA-256(pk <> slug)` -> base folding. A change here is a
    # silent break for every peer still deriving bases the old way, so the
    # numbers are fixed rather than recomputed from the implementation.
    test "app_base is stable across implementations" do
      assert Catenary.Apps.app_base(@pk, "example-app") == 656_499_575_700_829
      assert Catenary.Apps.app_base(@pk, "other-app") == 643_165_031_074_013
      assert Catenary.Apps.app_base(@pk, "a") == 836_526_981_358_417
    end

    test "kind sub-ids are fixed" do
      assert Catenary.Apps.manifest_log() == 562_949_953_421_313
      assert Catenary.Apps.artifact_log() == 562_949_953_421_314
      assert Catenary.Apps.source_log() == 562_949_953_421_315

      assert Catenary.Apps.kind_logs() == [
               Catenary.Apps.manifest_log(),
               Catenary.Apps.artifact_log(),
               Catenary.Apps.source_log()
             ]
    end

    test "the app family and its control log are what quagga_def registered" do
      assert Catenary.Apps.family() == 2
      assert Catenary.Apps.control_log() == 2777
      assert Catenary.Apps.control_log() == QuaggaDef.control_log(:app)
      assert Catenary.Apps.listing_logs() == QuaggaDef.logs_for_name(:listing)
      assert QuaggaDef.family_name(Catenary.Apps.family()) == :app
      assert QuaggaDef.families_for_control_log(2777) == [app: 2]
    end

    test "app bases fold exactly like backgammon game bases do" do
      # Same little-endian 48-bit fold of SHA-256, only the family tag differs.
      <<folded::unsigned-little-48, _::binary>> = :crypto.hash(:sha256, @pk <> "example-app")
      base = Catenary.Apps.app_base(@pk, "example-app")

      assert base == QuaggaDef.derived_log_base(folded, Catenary.Apps.family())
      assert Bitwise.band(base, 0x0000FFFFFFFFFFFF) == folded
      assert Bitwise.bsr(base, 48) == Catenary.Apps.family()
      assert QuaggaDef.reserved_base_log?(base)
    end
  end

  describe "slug rules" do
    test "strict charset, 1..64 bytes" do
      assert Catenary.Apps.valid_slug?("a")
      assert Catenary.Apps.valid_slug?("-")
      assert Catenary.Apps.valid_slug?(String.duplicate("a", 64))
      assert Catenary.Apps.valid_slug?("09az-")

      refute Catenary.Apps.valid_slug?("")
      refute Catenary.Apps.valid_slug?(String.duplicate("a", 65))
      refute Catenary.Apps.valid_slug?("Example-App")
      refute Catenary.Apps.valid_slug?("example-app ")
      refute Catenary.Apps.valid_slug?(" hour")
      refute Catenary.Apps.valid_slug?("h_o")
      refute Catenary.Apps.valid_slug?("héllo")
      refute Catenary.Apps.valid_slug?("h/l")
      refute Catenary.Apps.valid_slug?(42)
      refute Catenary.Apps.valid_slug?(nil)
    end

    test "slugs hash byte-for-byte: no canonicalization" do
      # If anything ever starts folding case, these three collapse into one.
      assert Catenary.Apps.app_base(@pk, "example-app") !=
               Catenary.Apps.app_base(@pk, "Example-App")

      assert Catenary.Apps.app_base(@pk, "example-app") !=
               Catenary.Apps.app_base(@pk, "example-app ")

      assert Catenary.Apps.app_base(@pk, "example-app") !=
               Catenary.Apps.app_base(@other_pk, "example-app")
    end

    test "validate_slug returns the input unchanged" do
      assert {:ok, "example-app"} = Catenary.Apps.validate_slug("example-app")
      assert {:error, :invalid_slug} = Catenary.Apps.validate_slug("Example-App")
      assert {:error, :invalid_slug} = Catenary.Apps.validate_slug(:example_app)
    end
  end

  describe "app ids" do
    test "round trip" do
      id = Catenary.Apps.app_id(@pk, "example-app")
      assert id == @pk <> "/example-app"
      assert {:ok, {@pk, "example-app"}} = Catenary.Apps.parse_app_id(id)
    end

    test "app_id rejects a bad slug" do
      assert {:error, :invalid_slug} = Catenary.Apps.app_id(@pk, "Example-App")
      assert {:error, :invalid_slug} = Catenary.Apps.app_id(@pk, "")
    end

    test "parse rejects malformed ids" do
      assert {:error, :bad_app_id} = Catenary.Apps.parse_app_id(@pk)
      assert {:error, :bad_app_id} = Catenary.Apps.parse_app_id("/example-app")
      assert {:error, :bad_app_id} = Catenary.Apps.parse_app_id("")
      assert {:error, :invalid_slug} = Catenary.Apps.parse_app_id(@pk <> "/Example-App")
      assert {:error, :bad_app_id} = Catenary.Apps.parse_app_id(nil)
    end
  end

  describe "log classification" do
    test "kind logs are app family but not channels" do
      for kind <- Catenary.Apps.kind_logs() do
        assert Catenary.Apps.app_family?(kind)
        assert Catenary.Apps.kind_log?(kind)
        refute Catenary.Apps.data_channel?(kind)
      end

      # Facet bits never change the classification
      assert Catenary.Apps.kind_log?(QuaggaDef.facet_log(Catenary.Apps.source_log(), 99))
      refute Catenary.Apps.data_channel?(QuaggaDef.facet_log(Catenary.Apps.source_log(), 99))
    end

    test "a derived channel is app family and not a kind log" do
      base = Catenary.Apps.app_base(@pk, "example-app")
      assert Catenary.Apps.app_family?(base)
      assert Catenary.Apps.data_channel?(base)
      refute Catenary.Apps.kind_log?(base)
      assert Catenary.Apps.data_channel?(QuaggaDef.facet_log(base, 7))
    end

    test "other logs classify correctly" do
      refute Catenary.Apps.app_family?(777)
      refute Catenary.Apps.kind_log?(777)
      refute Catenary.Apps.data_channel?(777)
      refute Catenary.Apps.app_family?(2777)

      refute Catenary.Apps.app_family?("777")
      refute Catenary.Apps.kind_log?(nil)
      refute Catenary.Apps.data_channel?(nil)
    end

    test "a channel base never collides with a kind sub-id" do
      # The collision is real but vanishingly unlikely (p ~= 3/2^48); what
      # matters is that classification keeps them apart when it happens.
      refute Catenary.Apps.data_channel?(Catenary.Apps.manifest_log())
    end
  end

  describe "verify_channel/3" do
    test "accepts the honest case, facetted or bare" do
      assert :ok = Catenary.Apps.verify_channel(@pk, @pk <> "/example-app", @channel)

      assert :ok =
               Catenary.Apps.verify_channel(
                 @pk,
                 @pk <> "/example-app",
                 QuaggaDef.facet_log(@channel, 3)
               )
    end

    test "rejects a slug that derives a different base" do
      assert {:error, :mismatch} =
               Catenary.Apps.verify_channel(
                 @pk,
                 @pk <> "/example-app",
                 Catenary.Apps.app_base(@pk, "other-app")
               )
    end

    test "rejects a claimed key that is not the signed author" do
      assert {:error, :author_mismatch} =
               Catenary.Apps.verify_channel(@other_pk, @pk <> "/example-app", @channel)
    end

    test "rejects a kind base" do
      assert {:error, :kind_base} =
               Catenary.Apps.verify_channel(
                 @pk,
                 @pk <> "/example-app",
                 Catenary.Apps.manifest_log()
               )
    end

    test "rejects logs outside the app family" do
      assert {:error, :not_app_log} =
               Catenary.Apps.verify_channel(@pk, @pk <> "/example-app", 777)
    end

    test "rejects malformed claims" do
      assert {:error, :invalid_slug} =
               Catenary.Apps.verify_channel(@pk, @pk <> "/Example-App", @channel)

      assert {:error, :bad_app_id} = Catenary.Apps.verify_channel(@pk, @pk, @channel)
      assert {:error, :bad_args} = Catenary.Apps.verify_channel(nil, nil, nil)
    end
  end

  describe "social_backlog?/1" do
    # The Unshown explorer and the explorebar badge read this rule: app
    # plumbing (release kind entries and channel messages) must never ask
    # for a one-at-a-time review, while announcements stay reviewable.
    test "app family records are plumbing, not backlog" do
      refute Catenary.Apps.social_backlog?({"ExampleAuthor1", Catenary.Apps.manifest_log(), 1})
      refute Catenary.Apps.social_backlog?({"ExampleAuthor1", Catenary.Apps.artifact_log(), 1})
      refute Catenary.Apps.social_backlog?({"ExampleAuthor1", Catenary.Apps.source_log(), 1})
      refute Catenary.Apps.social_backlog?({"ExampleAuthor1", @channel, 1})
    end

    test "announcements and other families stay on the backlog" do
      assert Catenary.Apps.social_backlog?({"ExampleAuthor1", Catenary.Apps.control_log(), 1})

      assert Catenary.Apps.social_backlog?(
               {"ExampleAuthor1", QuaggaDef.derived_log_base(0, 1), 1}
             )
    end
  end
end
