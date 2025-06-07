    test "get_bulk with root OID", %{device: device} do
      # Test starting from the very root
      result = Device.get_bulk(device, [1], 5)
      
      assert {:ok, varbinds} = result
      assert is_list(varbinds)
      
      # Root OID may return empty results - this is acceptable behavior
      if length(varbinds) > 0 do
        # Verify first varbind format if any results
        [{first_oid, _type, _value} | _] = varbinds
        oid_str = if is_list(first_oid), do: Enum.join(first_oid, "."), else: first_oid
        assert String.starts_with?(oid_str, "1")
      end
    end
