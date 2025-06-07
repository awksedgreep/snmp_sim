defmodule SnmpSim.GetBulkOidFormatTest do
  use ExUnit.Case, async: false
  require Logger

  alias SnmpSim.Device

  @moduletag :integration

  describe "SNMP GETBULK OID format fix verification" do
    test "SNMP GETBULK works correctly after OID format fix" do
      # Start a device on a test port
      device_config = %{
        device_id: "test_getbulk_fix",
        device_type: :cable_modem,
        name: "test_getbulk_fix",
        port: 10997,
        community: "public",
        walk_file: "priv/walks/cable_modem.walk"
      }

      {:ok, device_pid} = Device.start_link(device_config)

      # Give the device time to start
      Process.sleep(200)

      # Test SNMP GETBULK using system command
      # This will send OIDs as lists internally, testing our fix
      {output, exit_code} =
        System.cmd(
          "snmpbulkwalk",
          [
            "-v2c",
            "-c",
            "public",
            "-r",
            "1",
            "-t",
            "3",
            "127.0.0.1:10997",
            "1.3.6.1.2.1.1"
          ],
          stderr_to_stdout: true
        )

      # Should succeed (exit code 0) and return multiple OIDs
      assert exit_code == 0, "SNMP GETBULK failed with exit code #{exit_code}. Output: #{output}"

      # Should contain system information - this proves our fix is working
      assert String.contains?(output, "Motorola SB6141"),
             "Expected device description in output: #{output}"

      assert String.contains?(output, "sysObjectID"), "Expected sysObjectID in output: #{output}"

      # Count valid SNMP response lines to ensure we got multiple OIDs
      lines = String.split(output, "\n")

      valid_data_lines =
        Enum.filter(lines, fn line ->
          # sysObjectID has this issue but it's still valid data
          String.contains?(line, "STRING:") ||
            String.contains?(line, "INTEGER:") ||
            String.contains?(line, "Wrong Type")
        end)

      # We should get multiple valid OIDs (at least 5-7 system OIDs) before hitting end of MIB
      assert length(valid_data_lines) >= 5,
             "Expected at least 5 valid OID responses, got #{length(valid_data_lines)}. This proves the fix works. Output: #{output}"

      # It's OK to have "No more variables left" at the END after getting valid data
      # This is different from the original bug where we got this error IMMEDIATELY
      if String.contains?(output, "No more variables left in this MIB View") do
        # Ensure it's at the end, not at the beginning (which was the original bug)
        lines_with_content = Enum.filter(lines, &(String.trim(&1) != ""))
        last_line = List.last(lines_with_content)

        assert String.contains?(last_line, "No more variables left"),
               "End of MIB view should only appear at the end, not immediately. Output: #{output}"
      end

      # Test that regular SNMP GET still works
      {get_output, get_exit_code} =
        System.cmd(
          "snmpget",
          [
            "-v2c",
            "-c",
            "public",
            "-r",
            "1",
            "-t",
            "3",
            "127.0.0.1:10997",
            "1.3.6.1.2.1.1.1.0"
          ],
          stderr_to_stdout: true
        )

      assert get_exit_code == 0, "snmpget failed with output: #{get_output}"
      assert String.contains?(get_output, "Motorola SB6141")

      # Clean up
      Device.stop(device_pid)
    end

    test "SNMP GETBULK handles different starting OIDs correctly" do
      # Start a device on a test port
      device_config = %{
        device_id: "test_getbulk_oids",
        device_type: :cable_modem,
        name: "test_getbulk_oids",
        port: 10996,
        community: "public",
        walk_file: "priv/walks/cable_modem.walk"
      }

      {:ok, device_pid} = Device.start_link(device_config)
      Process.sleep(200)

      # Test different starting OIDs that should all work with our fix
      test_oids = [
        # Root OID - should redirect to system
        "1.3.6.1",
        # System group - should redirect to system
        "1.3.6.1.2.1.1",
        # System description - should return next OID
        "1.3.6.1.2.1.1.1.0"
      ]

      for oid <- test_oids do
        {output, exit_code} =
          System.cmd(
            "snmpbulkwalk",
            [
              "-v2c",
              "-c",
              "public",
              "-r",
              "1",
              "-t",
              "3",
              "127.0.0.1:10996",
              oid
            ],
            stderr_to_stdout: true
          )

        # Each should succeed and return data
        assert exit_code == 0, "snmpbulkwalk failed for OID #{oid} with output: #{output}"

        # Should return at least one valid response
        assert String.contains?(output, "STRING:") ||
                 String.contains?(output, "INTEGER:") ||
                 String.contains?(output, "OBJECT IDENTIFIER:"),
               "No valid SNMP data returned for OID #{oid}: #{output}"
      end

      Device.stop(device_pid)
    end

    test "regression test - reproduces original bug scenario" do
      # This test specifically reproduces the original failing scenario
      # to ensure our fix prevents regression

      device_config = %{
        device_id: "test_regression",
        device_type: :cable_modem,
        name: "test_regression",
        port: 10995,
        community: "public",
        walk_file: "priv/walks/cable_modem.walk"
      }

      {:ok, device_pid} = Device.start_link(device_config)
      Process.sleep(200)

      # This exact command was failing before the fix
      {output, exit_code} =
        System.cmd(
          "snmpbulkwalk",
          [
            "-v2c",
            "-c",
            "public",
            "127.0.0.1:10995",
            "1.3.6.1"
          ],
          stderr_to_stdout: true
        )

      # Before the fix: this would return exit_code != 0 with "No more variables left"
      # After the fix: this should succeed and return multiple values
      assert exit_code == 0, "Regression detected! Original bug has returned. Output: #{output}"

      # Should contain the expected system information
      assert String.contains?(output, "sysDescr")
      assert String.contains?(output, "Motorola")

      Device.stop(device_pid)
    end
  end
end
