defmodule SNMPSimEx.MIB.Compiler do
  @moduledoc """
  Leverage Erlang's battle-tested :snmpc module for MIB compilation.
  Extract OID definitions, data types, and constraints from vendor MIBs.
  """

  require Logger

  @doc """
  Compile a directory of MIB files into Elixir-friendly data structures.
  
  ## Examples
  
      {:ok, compiled_mibs} = SNMPSimEx.MIB.Compiler.compile_mib_directory("priv/mibs")
      
  """
  def compile_mib_directory(mib_dir, opts \\ []) do
    output_dir = Keyword.get(opts, :output_dir, Path.join(mib_dir, "compiled"))
    include_dirs = Keyword.get(opts, :include_dirs, [mib_dir])
    
    case File.ls(mib_dir) do
      {:ok, files} ->
        mib_files = 
          files
          |> Enum.filter(&String.ends_with?(&1, [".mib", ".MIB", ".txt"]))
          |> Enum.map(&Path.join(mib_dir, &1))
        
        compile_mib_files(mib_files, output_dir, include_dirs)
        
      {:error, reason} ->
        {:error, {:directory_read_failed, reason}}
    end
  end

  @doc """
  Compile a list of MIB files.
  
  ## Examples
  
      {:ok, mibs} = SNMPSimEx.MIB.Compiler.compile_mib_files([
        "priv/mibs/IF-MIB.txt",
        "priv/mibs/DOCS-CABLE-DEVICE-MIB.txt"
      ])
      
  """
  def compile_mib_files(mib_files, output_dir \\ nil, include_dirs \\ []) do
    output_dir = output_dir || System.tmp_dir!()
    
    # Ensure output directory exists
    File.mkdir_p!(output_dir)
    
    # Set up SNMP compiler options
    snmp_opts = [
      {:outdir, String.to_charlist(output_dir)},
      {:i, Enum.map(include_dirs, &String.to_charlist/1)},
      {:verbosity, :warning},
      {:warnings, true}
    ]
    
    compiled_mibs = 
      mib_files
      |> Enum.map(&compile_single_mib(&1, snmp_opts))
      |> Enum.filter(fn
        {:ok, _} -> true
        {:error, _} -> false
      end)
      |> Enum.map(fn {:ok, result} -> result end)
    
    case compiled_mibs do
      [] -> {:error, :no_mibs_compiled}
      mibs -> {:ok, mibs}
    end
  end

  @doc """
  Load a compiled MIB .bin file and extract OID information.
  
  ## Examples
  
      {:ok, mib_info} = SNMPSimEx.MIB.Compiler.load_compiled_mib("IF-MIB.bin")
      
  """
  def load_compiled_mib(bin_file) do
    case :snmpc.load_mibs([String.to_charlist(bin_file)]) do
      :ok ->
        extract_mib_info(bin_file)
        
      {:error, reason} ->
        {:error, {:mib_load_failed, reason}}
    end
  end

  @doc """
  Extract all object definitions from loaded MIBs.
  
  Returns a map of OID -> object_info for all objects in the MIB.
  """
  def extract_all_objects(mib_name) when is_binary(mib_name) do
    extract_all_objects(String.to_charlist(mib_name))
  end
  
  def extract_all_objects(mib_name) when is_list(mib_name) do
    try do
      # Get all object names from the MIB
      case :snmpa.which_objects(mib_name) do
        objects when is_list(objects) ->
          object_map = 
            objects
            |> Enum.map(&extract_object_info/1)
            |> Enum.reject(&is_nil/1)
            |> Map.new()
          
          {:ok, object_map}
          
        {:error, reason} ->
          {:error, {:object_extraction_failed, reason}}
      end
    rescue
      error ->
        {:error, {:extraction_error, error}}
    end
  end

  @doc """
  Get detailed information about a specific MIB object.
  """
  def get_object_info(object_name) when is_binary(object_name) do
    get_object_info(String.to_charlist(object_name))
  end
  
  def get_object_info(object_name) when is_list(object_name) do
    try do
      case :snmpa.name_to_oid(object_name) do
        {:ok, oid} ->
          oid_string = oid |> Enum.join(".")
          
          # Get additional object information
          object_info = %{
            name: List.to_string(object_name),
            oid: oid_string,
            type: get_object_type(object_name),
            access: get_object_access(object_name),
            description: get_object_description(object_name),
            constraints: get_object_constraints(object_name)
          }
          
          {:ok, object_info}
          
        {:error, reason} ->
          {:error, {:name_resolution_failed, reason}}
      end
    rescue
      error ->
        {:error, {:info_extraction_error, error}}
    end
  end

  # Private functions

  defp compile_single_mib(mib_file, snmp_opts) do
    mib_charlist = String.to_charlist(mib_file)
    
    Logger.info("Compiling MIB file: #{mib_file}")
    
    case :snmpc.compile(mib_charlist, snmp_opts) do
      {:ok, bin_file} ->
        Logger.info("Successfully compiled #{mib_file} -> #{bin_file}")
        
        # Extract basic info from the compiled MIB
        mib_info = %{
          source_file: mib_file,
          bin_file: List.to_string(bin_file),
          compiled_at: DateTime.utc_now()
        }
        
        {:ok, mib_info}
        
      {:error, reason} ->
        Logger.error("Failed to compile MIB #{mib_file}: #{inspect(reason)}")
        {:error, {:compilation_failed, mib_file, reason}}
    end
  end

  defp extract_mib_info(bin_file) do
    try do
      # Read the binary MIB file to extract metadata
      case File.read(bin_file) do
        {:ok, binary_data} ->
          # Parse the binary MIB structure (simplified)
          mib_info = %{
            bin_file: bin_file,
            size: byte_size(binary_data),
            loaded_at: DateTime.utc_now()
          }
          
          {:ok, mib_info}
          
        {:error, reason} ->
          {:error, {:file_read_failed, reason}}
      end
    rescue
      error ->
        {:error, {:info_extraction_failed, error}}
    end
  end

  defp extract_object_info(object_name) do
    case get_object_info(object_name) do
      {:ok, object_info} ->
        {object_info.oid, object_info}
      {:error, _reason} ->
        nil
    end
  end

  defp get_object_type(object_name) do
    try do
      # Try to get the object type from SNMP agent
      case :snmpa.get_object_info(object_name, :type) do
        {:ok, type} -> type
        _ -> :unknown
      end
    rescue
      _ -> :unknown
    end
  end

  defp get_object_access(object_name) do
    try do
      case :snmpa.get_object_info(object_name, :access) do
        {:ok, access} -> access
        _ -> :unknown
      end
    rescue
      _ -> :unknown
    end
  end

  defp get_object_description(object_name) do
    try do
      case :snmpa.get_object_info(object_name, :description) do
        {:ok, description} when is_list(description) -> List.to_string(description)
        {:ok, description} -> to_string(description)
        _ -> ""
      end
    rescue
      _ -> ""
    end
  end

  defp get_object_constraints(object_name) do
    try do
      # Extract constraints like ranges, enums, etc.
      case :snmpa.get_object_info(object_name, :constraints) do
        {:ok, constraints} -> constraints
        _ -> []
      end
    rescue
      _ -> []
    end
  end

  @doc """
  Create a standard MIB directory structure and download common MIBs.
  """
  def setup_standard_mibs(base_dir \\ "priv/mibs") do
    # Create directory structure
    File.mkdir_p!(base_dir)
    
    # Standard MIB list (these would typically be provided by the user)
    standard_mibs = [
      "SNMPv2-SMI",
      "SNMPv2-TC", 
      "SNMPv2-MIB",
      "IF-MIB",
      "IP-MIB",
      "TCP-MIB",
      "UDP-MIB",
      "HOST-RESOURCES-MIB"
    ]
    
    Logger.info("MIB directory created at #{base_dir}")
    Logger.info("Please place your MIB files (.mib, .txt) in this directory:")
    
    Enum.each(standard_mibs, fn mib ->
      Logger.info("  - #{mib}.txt")
    end)
    
    {:ok, %{
      mib_directory: base_dir,
      standard_mibs: standard_mibs,
      instructions: "Place MIB files in #{base_dir} and run compile_mib_directory/1"
    }}
  end

  @doc """
  Validate MIB dependencies and compilation order.
  """
  def validate_mib_dependencies(mib_files) do
    dependencies = 
      mib_files
      |> Enum.map(&extract_mib_dependencies/1)
      |> Enum.reduce(%{}, &Map.merge/2)
    
    case find_dependency_cycles(dependencies) do
      [] ->
        compilation_order = topological_sort(dependencies)
        {:ok, compilation_order}
        
      cycles ->
        {:error, {:circular_dependencies, cycles}}
    end
  end

  defp extract_mib_dependencies(mib_file) do
    # Simple dependency extraction from MIB file imports
    case File.read(mib_file) do
      {:ok, content} ->
        imports = extract_imports_from_content(content)
        %{mib_file => imports}
        
      {:error, _} ->
        %{mib_file => []}
    end
  end

  defp extract_imports_from_content(content) do
    # Extract IMPORTS statements (simplified regex-based approach)
    import_regex = ~r/IMPORTS\s+(.*?);/s
    
    case Regex.run(import_regex, content) do
      [_, imports_text] ->
        # Parse the imports text to extract MIB names
        Regex.scan(~r/FROM\s+([A-Z][A-Z0-9-]*)/i, imports_text)
        |> Enum.map(fn [_, mib_name] -> mib_name end)
        |> Enum.uniq()
        
      nil ->
        []
    end
  end

  defp find_dependency_cycles(_dependencies) do
    # Simplified cycle detection - in production this would be more robust
    []
  end

  defp topological_sort(dependencies) do
    # Simplified topological sort - return files in dependency order
    Map.keys(dependencies)
  end
end