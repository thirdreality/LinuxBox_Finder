#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <time.h>
#include <stdarg.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <net/if.h>
#include <arpa/inet.h>

#include "util.h"

bool get_mac_address(const char *ifname, char *mac_addr, size_t mac_len)
{
    struct ifreq ifr;
    int sock;

    if (!ifname || !mac_addr || mac_len < 18) {
        return false;
    }

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return false;
    }

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

    if (ioctl(sock, SIOCGIFHWADDR, &ifr) < 0) {
        close(sock);
        return false;
    }

    close(sock);

    snprintf(mac_addr, mac_len, "%02x:%02x:%02x:%02x:%02x:%02x",
             (unsigned char)ifr.ifr_hwaddr.sa_data[0],
             (unsigned char)ifr.ifr_hwaddr.sa_data[1],
             (unsigned char)ifr.ifr_hwaddr.sa_data[2],
             (unsigned char)ifr.ifr_hwaddr.sa_data[3],
             (unsigned char)ifr.ifr_hwaddr.sa_data[4],
             (unsigned char)ifr.ifr_hwaddr.sa_data[5]);

    return true;
}

bool get_ip_address(const char *ifname, char *ip_addr, size_t ip_len)
{
    struct ifreq ifr;
    int sock;

    if (!ifname || !ip_addr || ip_len < 16) {
        return false;
    }

    sock = socket(AF_INET, SOCK_DGRAM, 0);
    if (sock < 0) {
        return false;
    }

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);

    if (ioctl(sock, SIOCGIFADDR, &ifr) < 0) {
        close(sock);
        return false;
    }

    close(sock);

    struct sockaddr_in *ipaddr = (struct sockaddr_in *)&ifr.ifr_addr;
    snprintf(ip_addr, ip_len, "%s", inet_ntoa(ipaddr->sin_addr));

    return true;
}


// 简单的字符串查找函数
char* find_key_value(const char *json, const char *key, char *valueBuffer, size_t bufferSize) {
    char *keyPosition = strstr(json, key);
    if (keyPosition) {
        char *colonPosition = strchr(keyPosition, ':');
        if (colonPosition) {
            char *startQuote = strchr(colonPosition, '"');
            if (startQuote) {
                char *endQuote = strchr(startQuote + 1, '"');
                if (endQuote && (size_t)(endQuote - startQuote - 1) < bufferSize) {
                    strncpy(valueBuffer, startQuote + 1, endQuote - startQuote - 1);
                    valueBuffer[endQuote - startQuote - 1] = '\0';
                    return valueBuffer;
                }
            }
        }
    }
    return NULL;
}

#define BUFFER_SIZE 256
int check_advertising_manager() {
    FILE *fp;
    char buffer[BUFFER_SIZE];
    int method_exists = 0; // Flag to check if the method exists

    const char *command = "busctl --system introspect org.bluez /org/bluez/hci0";

    fp = popen(command, "r");
    if (fp == NULL) {
        fprintf(stderr, "Failed to run command\n");
        return 0;
    }

    // Read the output line by line
    while (fgets(buffer, BUFFER_SIZE, fp) != NULL) {
        if (strstr(buffer, "RegisterAdvertisement")) {
            method_exists = 1;
            break;
        }
    }

    pclose(fp);

    if (method_exists) {
        log_message("Method 'RegisterAdvertisement' exists.\n");
    } else {
        log_message("Method 'RegisterAdvertisement' does not exist.\n");
    }
    return method_exists;
}

/* restart_device, restart_wifi, factory_reset*/
int execute_command(const char *command, char *output, size_t output_size)
{
    FILE *fp;
    size_t bytes_read;

    if (!command || !output || output_size == 0) {
        return -1;
    }

    fp = popen(command, "r");
    if (!fp) {
        return -1;
    }

    bytes_read = fread(output, 1, output_size - 1, fp);
    if (bytes_read > 0) {
        output[bytes_read] = '\0';
    } else {
        output[0] = '\0';
    }

    return pclose(fp);
}

void log_message(const char *format, ...)
{
    va_list args;
    time_t now;
    struct tm *timeinfo;
    char timestamp[20];

    time(&now);
    timeinfo = localtime(&now);
    strftime(timestamp, sizeof(timestamp), "%Y-%m-%d %H:%M:%S", timeinfo);

    printf("[%s] ", timestamp);

    va_start(args, format);
    vprintf(format, args);
    va_end(args);

    printf("\n");
    fflush(stdout);
}
