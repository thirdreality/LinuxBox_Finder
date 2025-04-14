/*
 * Utility Functions Header File
 */

 #ifndef UTIL_H
 #define UTIL_H
 
 #include <stdlib.h>
 #include <stdbool.h>
 
 /**
  * Get the MAC address of a network interface
  * 
  * @param ifname Interface name (e.g., "wlan0")
  * @param mac_addr Buffer to store MAC address (format: XX:XX:XX:XX:XX:XX)
  * @param mac_len Size of mac_addr buffer
  * @return true on success, false on failure
  */
 bool get_mac_address(const char *ifname, char *mac_addr, size_t mac_len);
 
 /**
  * Get the IP address of a network interface
  * 
  * @param ifname Interface name (e.g., "wlan0")
  * @param ip_addr Buffer to store IP address
  * @param ip_len Size of ip_addr buffer
  * @return true on success, false on failure
  */
 bool get_ip_address(const char *ifname, char *ip_addr, size_t ip_len);
 
 /**
  * Execute a shell command and capture its output
  * 
  * @param command Command to execute
  * @param output Buffer to store command output
  * @param output_size Size of the output buffer
  * @return 0 on success, negative error code on failure
  */
 int execute_command(const char *command, char *output, size_t output_size);
 
 /**
  * Log message with timestamp
  * 
  * @param format Format string (printf style)
  * @param ... Variable arguments
  */
 void log_message(const char *format, ...);
 
 #endif /* UTIL_H */
 