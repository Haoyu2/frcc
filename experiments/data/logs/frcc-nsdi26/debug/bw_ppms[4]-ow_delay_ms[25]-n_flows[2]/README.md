# FRCC Debug Experiment Results

## Experiment Configuration

This directory contains the results from a debug run of the FRCC congestion control algorithm using the cc_bench framework.

### Run Parameters
- **Bandwidth (bw_ppms)**: 4 packets per millisecond (equivalent to ~3.2 Mbps)
- **One-way delay (ow_delay_ms)**: 25 ms
- **Buffer size (buf_size_bdp)**: 100 BDP (Buffer Delay Product)
- **Number of flows (n_flows)**: 2 concurrent TCP flows
- **Congestion Control Algorithm (cca)**: frcc
- **CCA Parameters**: None (default)
- **Jitter type**: ideal (no jitter)
- **RTT ratio**: 1 (symmetric RTT)
- **Duration**: 60 seconds
- **Overlap duration**: 180 seconds
- **Iperf log interval**: 1 second
- **Port**: 7111 (flow 1), 7112 (flow 2)

### Network Emulation Setup
- **Mahimahi traces**: 4ppms.trace for both uplink and downlink
- **Bottleneck queue**: droptail with 30,080,000 bytes capacity
- **Delay**: 25ms one-way delay
- **Jitter**: None (ideal link)

## Data Files

### Iperf3 JSON Logs (`flow[X]-*.json`)
- **Format**: Standard iperf3 JSON output
- **Contents**: Throughput, latency, retransmissions, and other TCP metrics per second
- **How to read**:
  - Load as JSON object
  - Key sections: `start`, `intervals` (per-second data), `end` (summary)
  - Throughput in `intervals[].sum.bits_per_second`
  - Retransmits in `intervals[].sum.retransmits`
  - Example parsing in Python:
    ```python
    import json
    with open('flow[1]-bw_ppms[4]-ow_delay_ms[25]-n_flows[2]-buf_size_bdp[100]-cca[frcc]-cca_param_tag[].json', 'r') as f:
        data = json.load(f)
    throughput = [interval['sum']['bits_per_second'] for interval in data['intervals']]
    ```

### Packet Capture CSVs (`flow[X]-*.pcap.csv`)
- **Format**: CSV with packet-level data extracted from tcpdump captures
- **Contents**: Timestamp, sequence number, ACK number, packet size, TCP flags, etc.
- **Columns**: time, seq, ack, len, flags, etc.
- **How to read**:
  - Load as pandas DataFrame
  - Analyze packet timing, sequence numbers for congestion window behavior
  - Example parsing in Python:
    ```python
    import pandas as pd
    df = pd.read_csv('flow[1]-bw_ppms[4]-ow_delay_ms[25]-n_flows[2]-buf_size_bdp[100]-cca[frcc]-cca_param_tag[].pcap.csv')
    # Plot sequence number over time
    df.plot(x='time', y='seq')
    ```

### Uplink Trace Log (`bw_ppms[4]-*.log`)
- **Format**: Mahimahi uplink queue log
- **Contents**: Timestamp, queue size, packet arrivals/departures
- **Columns**: time, queue_size, etc.
- **How to read**:
  - Analyze queue dynamics and bottleneck behavior
  - Useful for understanding buffer occupancy and packet loss

## Analysis Notes

- This is a debug run with minimal configuration for validation
- Both flows use FRCC CCA and compete for the same 4ppms bottleneck
- Expected behavior: Flows should achieve fair bandwidth sharing
- Duration is 60 seconds, but overlap is 180s (flows start staggered)

## Next Steps

- Run `python parse_pcap.py -i .` to generate summary statistics
- Use `python plot_all.sh` for visualization (if configured)
- Compare with other CCAs by changing the `cca` parameter
