/*
 * WiFi Manager Header File
 * Defines the interface for WiFi management operations
 */

 #ifndef WIFI_MANAGER_H
 #define WIFI_MANAGER_H
 
 #include <stdbool.h>
 
 #define WIFI_INTERFACE "wlan0"
 
 /* WiFi connection status structure */
 typedef struct {
     bool connected;
     char ssid[64];
     char ip_address[16];
     char mac_address[18];
     char error_message[128];
 } wifi_status_t;
 
 /**
  * Initialize the WiFi manager
  * 
  * @return 0 on success, negative error code on failure
  */
 int wifi_manager_init(void);
 
 /**
  * Cleanup and release resources used by the WiFi manager
  */
 void wifi_manager_cleanup(void);
 
 /**
  * Configure WiFi with the given SSID and password
  * 
  * @param ssid WiFi SSID to connect to
  * @param password WiFi password
  * @return 0 on success, negative error code on failure
  */
 int wifi_manager_configure(const char *ssid, const char *password);
 
 /**
  * Get the current WiFi connection status
  * 
  * @param status Pointer to wifi_status_t structure to fill
  * @return 0 on success, negative error code on failure
  */
 int wifi_manager_get_status(wifi_status_t *status);
 
 /**
  * Delete all saved WiFi networks
  * 
  * @return 0 on success, negative error code on failure
  */
 int wifi_manager_delete_networks(void);
 
 /**
  * Execute a special command
  * 
  * @param command Command to execute
  * @param response Buffer to store command response
  * @param response_size Size of the response buffer
  * @return 0 on success, negative error code on failure
  */
 int wifi_manager_execute_command(const char *command, char *response, size_t response_size);
 
 #endif /* WIFI_MANAGER_H */
 