Feature: Network and disk
  Below the graph's legend, the panel shows the whole Mac's current network
  and disk speeds, one decimal place, the unit growing from KB/s to MB/s to
  GB/s with the number. They keep no history, and each value is the one
  Activity Monitor shows in its Network and Disk tabs.

  @D117
  Scenario Outline: Network and disk match Activity Monitor
    Given Activity Monitor reads Data received/sec <received>, Data sent/sec <sent>, Data read/sec <read> and Data written/sec <written>
    When the user opens the panel
    Then the user sees the line "<net>"
    And the user sees the line "<disk>"

    Examples:
      | received | sent    | read     | written | net                          | disk                         |
      | 0 bytes  | 0 bytes | 0 bytes  | 0 bytes | Net ↓ 0.0 KB/s ↑ 0.0 KB/s    | Disk R 0.0 KB/s W 0.0 KB/s   |
      | 112.4 MB | 300 KB  | 210.0 MB | 1.2 GB  | Net ↓ 112.4 MB/s ↑ 300.0 KB/s | Disk R 210.0 MB/s W 1.2 GB/s |
