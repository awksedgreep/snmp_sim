defmodule SnmpSim.TestHelpers.PortHelper do
  @moduledoc """
  Simple helper functions for port allocation in tests.
  """
  
  alias SnmpSim.TestHelpers.PortAllocator

  @doc """
  Get a port for testing, ensuring PortAllocator is started.
  Falls back to server port range if PortAllocator fails.
  """
  def get_port do
    ensure_port_allocator_started()
    
    case PortAllocator.reserve_port() do
      {:ok, port} -> port
      {:error, _reason} -> 
        # Fallback to server port range (54,000-59,999)
        54_000 + :rand.uniform(6_000)
    end
  end
  
  @doc """
  Get a range of ports for testing.
  """
  def get_port_range(count) do
    ensure_port_allocator_started()
    
    case PortAllocator.reserve_port_range(count) do
      {:ok, {start_port, end_port}} -> start_port..end_port
      {:error, _reason} ->
        # Fallback to server port range (54,000-59,999) with enough space
        available_space = 6_000 - count
        start_port = 54_000 + :rand.uniform(max(1, available_space))
        start_port..(start_port + count - 1)
    end
  end
  
  @doc """
  Get a deterministic range of ports for testing based on a name.
  This helps avoid port conflicts between tests.
  """
  def get_port_range(test_name, count) do
    # Create a deterministic hash from the test name
    hash = :erlang.phash2(test_name, 1000)
    
    # Use different base ranges to avoid conflicts - all within valid port range (0-65535)
    base_port = case hash do
      n when n < 200 -> 50_000 + (n * 20)  # 50,000-53,999
      n when n < 400 -> 54_000 + ((n - 200) * 20)  # 54,000-57,999  
      n when n < 600 -> 58_000 + ((n - 400) * 20)  # 58,000-61,999
      n when n < 800 -> 62_000 + ((n - 600) * 15)  # 62,000-64,999
      n -> 65_000 + ((n - 800) * 2)  # 65,000-65,399 (stay well below 65535)
    end
    
    start_port = base_port
    end_port = start_port + count - 1
    
    # Ensure we don't exceed the maximum valid port number
    if end_port > 65_535 do
      # If we would exceed, use a safe range in the high 50000s
      safe_start = 59_000 + rem(hash, 1000)
      safe_end = safe_start + count - 1
      if safe_end <= 65_535 do
        safe_start..safe_end
      else
        # Last resort: use a small range in the 50000s
        fallback_start = 50_000 + rem(hash, 100)
        fallback_start..(fallback_start + count - 1)
      end
    else
      start_port..end_port
    end
  end
  
  @doc """
  Release a port back to the pool.
  """
  def release_port(port) do
    case GenServer.whereis(PortAllocator) do
      nil -> :ok
      _pid -> PortAllocator.release_port(port)
    end
  end
  
  @doc """
  Release a port range back to the pool.
  """
  def release_port_range(start_port, end_port) do
    case GenServer.whereis(PortAllocator) do
      nil -> :ok
      _pid -> PortAllocator.release_port_range(start_port, end_port)
    end
  end
  
  defp ensure_port_allocator_started do
    case GenServer.whereis(PortAllocator) do
      nil -> 
        {:ok, _pid} = PortAllocator.start_link()
      _pid -> 
        :ok
    end
  end
end