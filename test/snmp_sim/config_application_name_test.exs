defmodule SnmpSim.ConfigApplicationNameTest do
  @moduledoc """
  Tests to ensure configuration files use the correct application name.

  This prevents the regression where config files used :snmp_sim_ex 
  instead of the correct :snmp_sim application name.
  """

  use ExUnit.Case, async: false

  describe "Configuration application name consistency" do
    test "mix.exs defines application name as :snmp_sim" do
      # Read mix.exs and verify the application name
      mix_content = File.read!("mix.exs")

      # Should contain 'app: :snmp_sim'
      assert String.contains?(mix_content, "app: :snmp_sim")

      # Should not contain the old incorrect name
      refute String.contains?(mix_content, "app: :snmp_sim_ex")
    end

    test "config files reference correct application name" do
      # Check config files use :snmp_sim not :snmp_sim_ex
      config_files = [
        "config/config.exs",
        "config/dev.exs",
        "config/prod.exs",
        "config/test.exs"
      ]

      Enum.each(config_files, fn config_file ->
        if File.exists?(config_file) do
          content = File.read!(config_file)

          # Should not contain references to the old incorrect name
          refute String.contains?(content, ":snmp_sim_ex"),
                 "#{config_file} contains incorrect application name :snmp_sim_ex"
        end
      end)
    end

    test "application can start without configuration errors" do
      # This test ensures the application name mismatch doesn't cause startup errors
      # The error was: "You have configured application :snmp_sim in your configuration file, but the application is not available"

      # Stop the application if it's running
      Application.stop(:snmp_sim)

      # Try to start it - should not raise configuration errors
      assert {:ok, _} = Application.ensure_all_started(:snmp_sim)

      # Ensure application stays running for other tests
      # (No need to stop it again since test_helper.exs starts it)
    end
  end
end
