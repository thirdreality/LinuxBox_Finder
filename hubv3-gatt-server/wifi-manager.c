#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <stdbool.h>
#include <sys/types.h>
#include <ifaddrs.h>
#include <netinet/in.h>
#include <net/if.h>

#include "wifi-manager.h"
#include "util.h"


#define MAX_COMMAND_LEN 512
#define MAX_RESPONSE_LEN 4096

/* Static function prototypes */
static bool check_wifi_connected(void);

int wifi_manager_init(void)
{
    log_message("Initializing WiFi manager");
    
    /* Check if WiFi interface exists */
    char mac_addr[18];
    if (!get_mac_address(WIFI_INTERFACE, mac_addr, sizeof(mac_addr))) {
        log_message("WiFi interface %s not found", WIFI_INTERFACE);
        return -1;
    }
    
    log_message("WiFi interface %s initialized. MAC: %s", WIFI_INTERFACE, mac_addr);
    return 0;
}

void wifi_manager_cleanup(void)
{
    log_message("Cleaning up WiFi manager");
    /* Nothing to clean up for now */
}

#if 0
int wifi_manager_configure(const char *ssid, const char *password)
{
    char command[MAX_COMMAND_LEN];
    char response[MAX_RESPONSE_LEN];
    
    if (!ssid || strlen(ssid) == 0) {
        log_message("Invalid SSID");
        return -1;
    }
    
    log_message("Configuring WiFi. SSID: %s", ssid);
    
    /* First, check if the connection already exists */
    snprintf(command, sizeof(command), "nmcli -t connection show | grep '%s'", ssid);
    if (execute_command(command, response, sizeof(response)) == 0 && strlen(response) > 0) {
        /* Connection exists, delete it first */
        log_message("Connection for %s already exists, deleting it first", ssid);
        snprintf(command, sizeof(command), "nmcli connection delete '%s'", ssid);
        execute_command(command, response, sizeof(response));
    }
    
    /* Create a new connection */
    if (password && strlen(password) > 0) {
        /* Secured network */
        snprintf(command, sizeof(command), 
                 "nmcli device wifi connect '%s' password '%s'", 
                 ssid, password);
    } else {
        /* Open network */
        snprintf(command, sizeof(command), 
                 "nmcli device wifi connect '%s'", 
                 ssid);
    }
    
    if (execute_command(command, response, sizeof(response)) != 0) {
        log_message("Failed to connect to WiFi network: %s", response);
        return -1;
    }
    
    /* Wait for the connection to be established */
    int timeout = 20; /* 20 seconds timeout */
    while (timeout > 0) {
        if (check_wifi_connected()) {
            log_message("Successfully connected to WiFi network: %s", ssid);
            return 0;
        }
        sleep(1);
        timeout--;
    }
    
    log_message("Timed out waiting for WiFi connection");
    return -2;
}
#endif


int wifi_manager_configure(const char *ssid, const char *password) {
    char command[MAX_COMMAND_LEN];
    char response[MAX_RESPONSE_LEN];
    
    if (!ssid || strlen(ssid) == 0) {
        log_message("Invalid SSID");
        return -1;
    }
    
    log_message("Configuring WiFi. SSID: %s", ssid);
    
    /* Check the currently active connection's SSID */
    snprintf(command, sizeof(command), "nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2");
    if (execute_command(command, response, sizeof(response)) == 0) {
        // 去除行末的换行符
        response[strcspn(response, "\n")] = '\0'; 
        if (strcmp(ssid, response) == 0) {
            log_message("Already connected to the requested SSID: %s", ssid);
            return 0;
        }
    }
    
    /* First, check if the desired connection exists */
    snprintf(command, sizeof(command), "nmcli -t --fields NAME connection show | grep -x '%s'", ssid);
    if (execute_command(command, response, sizeof(response)) == 0 && strlen(response) > 0) {
        /* Connection exists, delete it */
        log_message("Connection for %s already exists, deleting it first", ssid);
        snprintf(command, sizeof(command), "nmcli connection delete id '%s'", ssid);
        if (execute_command(command, response, sizeof(response)) != 0) {
            log_message("Failed to delete existing connection: %s", response);
            return -1;
        }
    }
    
    /* Create a new connection */
    if (password && strlen(password) > 0) {
        /* Secured network */
        snprintf(command, sizeof(command), 
                 "nmcli device wifi connect '%s' password '%s'", 
                 ssid, password);
    } else {
        /* Open network */
        snprintf(command, sizeof(command), 
                 "nmcli device wifi connect '%s'", 
                 ssid);
    }
    
    if (execute_command(command, response, sizeof(response)) != 0) {
        log_message("Failed to connect to WiFi network: %s", response);
        return -1;
    }
    
    /* Wait for the connection to be established */
    int timeout = 20; /* 20 seconds timeout */
    while (timeout > 0) {
        if (check_wifi_connected()) {
            log_message("Successfully connected to WiFi network: %s", ssid);
            return 0;
        }
        sleep(1);
        timeout--;
    }
    
    log_message("Timed out waiting for WiFi connection");
    return -2;
}

int wifi_manager_get_status(wifi_status_t *status)
{
    char command[MAX_COMMAND_LEN];
    char response[MAX_RESPONSE_LEN];
    
    if (!status) {
        return -1;
    }
    
    /* Initialize the status structure */
    memset(status, 0, sizeof(wifi_status_t));
    
    /* Check if connected */
    status->connected = check_wifi_connected();
    
    if (status->connected) {
        /* Get SSID */
        snprintf(command, sizeof(command), 
                 "nmcli -t -f active,ssid dev wifi | grep '^yes:' | cut -d ':' -f 2");
        if (execute_command(command, response, sizeof(response)) == 0 && strlen(response) > 0) {
            /* Remove trailing newline */
            response[strcspn(response, "\n")] = 0;
            log_message("nmcli response: %s", response);

            strncpy(status->ssid, response, sizeof(status->ssid) - 1);
        }
        
        /* Get IP address */
        if (!get_ip_address(WIFI_INTERFACE, status->ip_address, sizeof(status->ip_address))) {
            strncpy(status->ip_address, "Unknown", sizeof(status->ip_address) - 1);
        }

        log_message("ip_address: %s", status->ip_address);
        
        /* Get MAC address */
        if (!get_mac_address(WIFI_INTERFACE, status->mac_address, sizeof(status->mac_address))) {
            strncpy(status->mac_address, "Unknown", sizeof(status->mac_address) - 1);
        }

        log_message("mac_address: %s", status->mac_address);
    } else {
        strncpy(status->error_message, "Not connected to any WiFi network", sizeof(status->error_message) - 1);
    }
    
    return 0;
}

int wifi_manager_delete_networks(void)
{
    char line[MAX_COMMAND_LEN];
    log_message("Deleting all saved WiFi networks");

    FILE *fp;
    fp = popen("nmcli -t -f uuid connection", "r");
    if (fp == NULL) {
        fprintf(stderr, "Failed to run nmcli command\n");
        return 1;
    }

    while (fgets(line, sizeof(line), fp) != NULL) {
        line[strcspn(line, "\n")] = '\0';
        if (strlen(line) > 0) {
            char command[128];
            snprintf(command, sizeof(command), "nmcli connection delete uuid %s", line);

            int result = system(command);
            if (result != 0) {
                log_message("Failed to delete connection with UUID: %s", line);
            } else {
                log_message("Successfully deleted connection with UUID: %s", line);
            }
        }
    }

    pclose(fp);
    return 0;
}

int wifi_manager_execute_command(const char *command, char *response, size_t response_size)
{
    if (!command || !response || response_size == 0) {
        return -1;
    }
    
    log_message("Executing command: %s", command);
    
    /* Handle different commands */
    if (strcmp(command, "restart_wifi") == 0) {
        /* Restart WiFi interface */
        char cmd[MAX_COMMAND_LEN];
        snprintf(cmd, sizeof(cmd), "nmcli radio wifi off && sleep 1 && nmcli radio wifi on");
        return execute_command(cmd, response, response_size);
    } else if (strcmp(command, "restart_device") == 0) {
        /* Schedule a system restart after a short delay */
        log_message("Scheduling system restart");
        snprintf(response, response_size, "Device will restart in 5 seconds");
        /* Use a fork to avoid blocking the main process */
        if (fork() == 0) {
            sleep(5);
            system("reboot");
            exit(0);
        }
        return 0;
    } else if (strcmp(command, "factory_reset") == 0) {
        /* Delete all WiFi networks first */
        wifi_manager_delete_networks();
        
        /* Could add more factory reset operations here if needed */
        snprintf(response, response_size, "Factory reset completed");
        return 0;
    } else {
        /* Unknown command */
        snprintf(response, response_size, "Unknown command: %s", command);
        return -1;
    }
}

/* Static helper functions */

static bool check_wifi_connected(void)
{
    char command[MAX_COMMAND_LEN] = "nmcli -t -f GENERAL.STATE device show wlan0";
    char response[MAX_RESPONSE_LEN];
    
    if (execute_command(command, response, sizeof(response)) == 0 && 
        strlen(response) > 0 && 
        strstr(response, "(connected)") != NULL) {
        return true;
    }
    
    return false;
}
