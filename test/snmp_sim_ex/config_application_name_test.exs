defmodule SnmpSim.ConfigApplicationNameTest do
  @moduledoc """
  Tests to ensure configuration files use the correct application name.
  
  This prevents the regression where config files used :snmp_sim_ex 
  instead of the correct :snmp_sim application name.
  """
  
  use ExUnit.Case, async: true
  
  describe "Configuration application name consistency" do
    test "mix.exs defines application name as :snmp_sim" do
      # Read mix.exs and verify the application name
      mix_content = File.read!("mix.exs")
      
      # Should contain 'app: :snmp_sim'
      assert mix_content =~ ~r/app:\s*:snmp_sim/
      refute mix_content =~ ~r/app:\s*:snmp_sim_ex/
    end
    
    test "config files use correct application name :snmp_sim" do
      config_files = [
        "config/config.exs",
        "config/dev.exs", 
        "config/test.exs",
        "config/prod.exs"
      ]
      
      for config_file <- config_files do
        if File.exists?(config_file) do
          content = File.read!(config_file)
          
          # Should not contain the old incorrect name
          refute content =~ ~r/:snmp_sim_ex/,
            "#{config_file} still contains incorrect application name :snmp_sim_ex"
          
          # If it configures the app, it should use the correct name
          if content =~ ~r/config\s+:/ do
            assert content =~ ~r/:snmp_sim/,
              "#{config_file} should use correct application name :snmp_sim"
          end
        end
      end
    end
    
    test "application can start without configuration errors" do
      # This test ensures the application name mismatch doesn't cause startup errors
      # The error was: "You have configured application :snmp_sim_ex in your configuration file, but the application is not available"
      
      # Stop the application if it's running
      Application.stop(:snmp_sim)
      
      # Try to start it - should not raise configuration errors
      assert {:ok, _} = Application.ensure_all_started(:snmp_sim)
      
      # Clean up
      Application.stop(:snmp_sim)
    end
  end
end
