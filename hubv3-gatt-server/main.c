#include <glib.h>
#include <stdio.h>
#include <stdbool.h>
#include <signal.h>
#include <unistd.h>
#include "adapter.h"
#include "device.h"
#include "logger.h"
#include "agent.h"
#include "application.h"
#include "advertisement.h"
#include "utility.h"
#include "parser.h"

#include "wifi-manager.h"
#include "util.h"

#define TAG "Main"

#define HUBV3_CONFIG_SERVICE_UUID "6e400000-0000-4e98-8024-bc5b71e0893e"

// 查看wifi状态: 使用json指令：读
#define HUBV3_WIFI_STATUS_CHAR_UUID "6e400001-0000-4e98-8024-bc5b71e0893e"

// 配置wifi，使用json指令：写
#define HUBV3_WIFI_CONFIG_CHAR_UUID "6e400002-0000-4e98-8024-bc5b71e0893e"

// 查询系统配置：只读
#define HUBV3_SYSINFO_CHAR_UUID "6e400003-0000-4e98-8024-bc5b71e0893e"

// 自定义指令, 读写
#define HUBV3_CUSTOM_COMMAND_CHAR_UUID "6e400004-0000-4e98-8024-bc5b71e0893e"

GMainLoop *loop = NULL;
Adapter *default_adapter = NULL;
Advertisement *advertisement = NULL;
Application *app = NULL;
bool notify = true;

static void on_powered_state_changed(Adapter *adapter, gboolean state)
{
    log_debug(TAG, "powered '%s' (%s)", state ? "on" : "off", binc_adapter_get_path(adapter));
}

static void on_central_state_changed(Adapter *adapter, Device *device)
{
    char *deviceToString = binc_device_to_string(device);
    log_debug(TAG, deviceToString);
    g_free(deviceToString);

    log_debug(TAG, "remote central %s is %s", binc_device_get_address(device), binc_device_get_connection_state_name(device));
    ConnectionState state = binc_device_get_connection_state(device);
    if (state == BINC_CONNECTED)
    {
        binc_adapter_stop_advertising(adapter, advertisement);
    }
    else if (state == BINC_DISCONNECTED)
    {
        binc_adapter_start_advertising(adapter, advertisement);
    }
}

static void local_server_write_char(const Application *app, 
    const char * service_uuid, 
    const char * char_uuid, 
    const char * result)
{
    if(result == NULL || strlen(result) == 0)
    {
        return;
    }

    int length = strlen(result);
    GByteArray *byteArray = g_byte_array_sized_new(length);
    g_byte_array_append(byteArray, result, length);

    if(notify)
    {
        log_debug(TAG, "Response notify : %s", result);
        binc_application_notify(app, service_uuid, char_uuid, byteArray);
    }
    else
    {
        log_debug(TAG, "Response write : %s", result);
        binc_application_set_char_value(app, service_uuid, char_uuid, byteArray);
    }
    g_byte_array_free(byteArray, TRUE);
}


//!< 远端App执行了BLE Read的操作， 本地填充结果
static const char *on_local_char_read(const Application *application,
                                      const char *address,
                                      const char *service_uuid,
                                      const char *char_uuid)
{

    log_debug(TAG, "%s: %s", __func__, char_uuid);

    if (g_str_equal(service_uuid, HUBV3_CONFIG_SERVICE_UUID))
    {
        if (g_str_equal(char_uuid, HUBV3_SYSINFO_CHAR_UUID))
        {
            log_debug(TAG, "on_local_char_read Command: Query System Status");
            const guint8 bytes[] = {'{', 'o', 'k', '}'};
            GByteArray *byteArray = g_byte_array_sized_new(sizeof(bytes));
            g_byte_array_append(byteArray, bytes, sizeof(bytes));
            binc_application_set_char_value(application, service_uuid, char_uuid, byteArray);
            g_byte_array_free(byteArray, TRUE);
            return NULL;
        }
    }

    return BLUEZ_ERROR_REJECTED;
}

//!< 远端App执行了BLE Write的操作，接收从移动App端的指令
static const char *on_local_char_write(const Application *application,
                                       const char *address,
                                       const char *service_uuid,
                                       const char *char_uuid, 
                                       GByteArray *byteArray)
{
    log_debug(TAG, "Receive request from MobileApp: %s, %s", address, char_uuid);
    return NULL;
}

// This function is called after a write request was validates and the characteristic value was set
void on_local_char_updated(const Application *application, const char *service_uuid,
    const char *char_uuid, GByteArray *byteArray) {
    // GString *result = g_byte_array_as_hex(byteArray);
    // log_debug(TAG, "on_local_char_updated: characteristic <%s> updated to <%s>", char_uuid, result->str);
    // g_string_free(result, TRUE);

    if (g_str_equal(service_uuid, HUBV3_CONFIG_SERVICE_UUID))
    {
        if (g_str_equal(char_uuid, HUBV3_WIFI_CONFIG_CHAR_UUID))
        {
            if(byteArray != NULL && byteArray->len > 0)
            {
                char *request = byteArray->data;
                log_debug(TAG, "on_local_char_write Get WIFI_CONFIG request : %s", request);
                /* Expected JSON format: {"action":"connect","ssid":"network_name","password":"network_password"} */

                char action[64] = {0};
                find_key_value(request, "action", action, 64);
                log_debug(TAG, "action: %s", action);

                char json_status[128] = {0};
                if(strcmp("connect", action) == 0)
                {
                    int result = -1;
                    char ssid[64] = {0};
                    char password[64] = {0};

                    find_key_value(request, "ssid", ssid, 64);
                    find_key_value(request, "password", password, 64);

                    if(strlen(ssid) > 0 && strlen(ssid) > 0)
                    {
                        result = wifi_manager_configure(ssid, password);
                    }

                    snprintf(json_status, sizeof(json_status),
                    "{"
                    "\"command\":%s,"
                    "\"success\":\"%s\","
                    "}",
                    action,
                    result == 0 ? "true":"false"); 

                    local_server_write_char(app, service_uuid, char_uuid, json_status); 
                    
                    return NULL;
                }
                else if(strcmp("delete_connects", action) == 0)
                {                  
                    wifi_manager_delete_networks();
                    snprintf(json_status, sizeof(json_status),
                    "{"
                    "\"command\":%s,"
                    "\"success\":\"%s\","
                    "}",
                    action,
                    "true");
                    
                    local_server_write_char(app, service_uuid, char_uuid, json_status); 
                    return NULL;
                }
            } 
        }
        else if (g_str_equal(char_uuid, HUBV3_CUSTOM_COMMAND_CHAR_UUID))
        {
            char json_status[128] = {0};
            if(byteArray != NULL && byteArray->len > 0)
            {
                char *request = byteArray->data;
                log_debug(TAG, "on_local_char_write Get CUSTOM_COMMAND request : %s", request);

                char exec_result[256] = {0};
                int result = wifi_manager_execute_command(request, exec_result, 256);

                snprintf(json_status, sizeof(json_status),
                "{"
                "\"command\":%s,"
                "\"success\":\"%s\","
                "}",
                request,
                result==0?"true":"false");
            }
            else
            {
                snprintf(json_status, sizeof(json_status),
                "{"
                "\"command\":%s,"
                "\"success\":\"%s\","
                "}",
                "unknown",
                "true");
            }

            local_server_write_char(app, service_uuid, char_uuid, json_status);
            return NULL;
        }
    }    
}

//不附加参数的指令可以考虑用notify
static void on_local_char_start_notify(const Application *application, const char *service_uuid, const char *char_uuid)
{
    log_debug(TAG, "on start notify");
    // if (g_str_equal(service_uuid, HUBV3_CONFIG_SERVICE_UUID) && g_str_equal(char_uuid, CHARACTERISTIC_UUID_TX)) {
    //     notify = true;
    // }
    log_debug(TAG, "on start notify %s", char_uuid);

    if (g_str_equal(service_uuid, HUBV3_CONFIG_SERVICE_UUID))
    {
        if (g_str_equal(char_uuid, HUBV3_WIFI_STATUS_CHAR_UUID))
        {
            notify = true;
            log_debug(TAG, "on start notify Command: Query WiFi Status");
            // 查询wifi，返回wifi状态
            char json_status[512] = {0};
            wifi_status_t status;
            if (wifi_manager_get_status(&status) == 0) {
                snprintf(json_status, sizeof(json_status),
                         "{"
                         "\"connected\":%s,"
                         "\"ssid\":\"%s\","
                         "\"ip_address\":\"%s\","
                         "\"mac_address\":\"%s\""
                         "}",
                         status.connected ? "true" : "false",
                         status.ssid,
                         status.ip_address,
                         status.mac_address);                
            }else
            {
                snprintf(json_status, sizeof(json_status),
                         "{"
                         "\"connected\":%s,"
                         "\"ssid\":\"%s\","
                         "\"ip_address\":\"%s\","
                         "\"mac_address\":\"%s\""
                         "}",
                         "false",
                         "none",
                         "0.0.0.0",
                         "00:00:00:00:00:00");      
            }

            log_debug(TAG, "Wifi Status: %s", json_status);
            log_debug(TAG, "Wifi Status length: %d", strlen(json_status));
            log_debug(TAG, "Wifi Status sizeof: %d", sizeof(json_status));

            local_server_write_char(application, service_uuid, char_uuid, json_status);

            return;
        } else if (g_str_equal(char_uuid, HUBV3_SYSINFO_CHAR_UUID))
        {
            log_debug(TAG, "on start notify Command: Query System Status");
        }
        else
        {
            notify = true;
        }
    }    
}

static void on_local_char_stop_notify(const Application *application, const char *service_uuid, const char *char_uuid)
{
    log_debug(TAG, "on stop notify");
    if (g_str_equal(service_uuid, HUBV3_CONFIG_SERVICE_UUID))
    {    
        notify = false;
    }
}



static gboolean cleanup_callback(gpointer data)
{
    if (app != NULL)
    {
        log_debug(TAG, "Unregister application ...");
        binc_adapter_unregister_application(default_adapter, app);
        binc_application_free(app);
        app = NULL;
    }

    if (advertisement != NULL)
    {
        log_debug(TAG, "Stop advertising ...");
        binc_adapter_stop_advertising(default_adapter, advertisement);
        binc_advertisement_free(advertisement);
    }

    if (default_adapter != NULL)
    {
        binc_adapter_free(default_adapter);
        default_adapter = NULL;
    }

    log_debug(TAG, "Main loop quit ...");
    g_main_loop_quit((GMainLoop *)data);
    return FALSE;
}

static void cleanup_handler(int signo)
{
    if (signo == SIGINT)
    {
        log_error(TAG, "received SIGINT");
        cleanup_callback(loop);
    }
}

int main(int argc, char **argv)
{
    // Get a DBus connection
    GDBusConnection *dbusConnection = g_bus_get_sync(G_BUS_TYPE_SYSTEM, NULL, NULL);

    // Setup handler for CTRL+C
    if (signal(SIGINT, cleanup_handler) == SIG_ERR)
    {
        log_error(TAG, "can't catch SIGINT");
    }

    // Setup mainloop
    loop = g_main_loop_new(NULL, FALSE);

    int max_retry = 15;
    int retry_time = 0;
    // Get the default default_adapter
    default_adapter = binc_adapter_get_default(dbusConnection);
    while (default_adapter == NULL)
    {
        sleep(2);

        log_debug(TAG, "Search bluetooth ...");
        default_adapter = binc_adapter_get_default(dbusConnection);

        retry_time +=1;
        if (retry_time > max_retry)
        {
            log_debug(TAG, "No bluetooth device found");
            break;
        }
    }

    char local_name[32] = {0};
    local_name[0] = '3';
    local_name[1] = 'R';
    local_name[2] = 'H';
    local_name[3] = 'U';
    local_name[4] = 'B';

    if (default_adapter != NULL)
    {
        log_debug(TAG, "using default_adapter '%s'", binc_adapter_get_path(default_adapter));

        // Make sure the adapter is on
        binc_adapter_set_powered_state_cb(default_adapter, &on_powered_state_changed);
        if (!binc_adapter_get_powered_state(default_adapter))
        {
            binc_adapter_power_on(default_adapter);
        }

        // Setup remote central connection state callback
        binc_adapter_set_remote_central_cb(default_adapter, &on_central_state_changed);

        char mac_addr[18] = {0};
        if (get_mac_address(WIFI_INTERFACE, mac_addr, sizeof(mac_addr)))
        {
            log_debug(TAG, "using mac-address '%s'", mac_addr);

            local_name[5] = '-';
            int k = 6;

            /* Add MAC address to manufacturer data */
            for (int i = 0; i < 18; i++)
            {
                if (mac_addr[i] == 0)
                    break;
                if (mac_addr[i] == ':')
                    continue;

                char c = mac_addr[i];
                if (c >= 'a' && c <= 'f') {
                    local_name[k] = mac_addr[i] - 32;
                }
                else
                {
                    local_name[k] = mac_addr[i];
                }

                k = k + 1;
            }

            log_debug(TAG, "using local name '%s'", local_name);
        }
        else
        {
            local_name[5] = '-';
            local_name[6] = '-';
            local_name[7] = '-';

            log_debug(TAG, "using local name '%s'", local_name);
        }

        retry_time = 0;
        while(check_advertising_manager() == 0)
        {
            log_debug(TAG, "AdvertisingManager not found");
            sleep(2);

            retry_time +=1;
            if (retry_time > max_retry)
            {
                log_debug(TAG, "No AdvertisingManager interface found");
                break;
            }            
        }

        // Setup advertisement
        GPtrArray *adv_service_uuids = g_ptr_array_new();
        g_ptr_array_add(adv_service_uuids, HUBV3_CONFIG_SERVICE_UUID);

        advertisement = binc_advertisement_create();
        binc_advertisement_set_local_name(advertisement, local_name);
        binc_advertisement_set_services(advertisement, adv_service_uuids);
        g_ptr_array_free(adv_service_uuids, TRUE);
        binc_adapter_start_advertising(default_adapter, advertisement);

        // Start application
        app = binc_create_application(default_adapter);
        binc_application_add_service(app, HUBV3_CONFIG_SERVICE_UUID);

        binc_application_add_characteristic(
            app,
            HUBV3_CONFIG_SERVICE_UUID,
            HUBV3_WIFI_STATUS_CHAR_UUID,
            GATT_CHR_PROP_INDICATE);

        binc_application_add_characteristic(
            app,
            HUBV3_CONFIG_SERVICE_UUID,
            HUBV3_WIFI_CONFIG_CHAR_UUID,
            GATT_CHR_PROP_WRITE|GATT_CHR_PROP_INDICATE);

        binc_application_add_characteristic(
            app,
            HUBV3_CONFIG_SERVICE_UUID,
            HUBV3_SYSINFO_CHAR_UUID,
            GATT_CHR_PROP_INDICATE);

        binc_application_add_characteristic(
            app,
            HUBV3_CONFIG_SERVICE_UUID,
            HUBV3_CUSTOM_COMMAND_CHAR_UUID,
            GATT_CHR_PROP_WRITE|GATT_CHR_PROP_INDICATE);

        binc_application_set_char_read_cb(app, &on_local_char_read);
        binc_application_set_char_write_cb(app, &on_local_char_write);
        binc_application_set_char_start_notify_cb(app, &on_local_char_start_notify);
        binc_application_set_char_stop_notify_cb(app, &on_local_char_stop_notify);
        binc_application_set_char_updated_cb(app, &on_local_char_updated);
        binc_adapter_register_application(default_adapter, app);
    }
    else
    {
        log_debug("MAIN", "No default_adapter found");
    }

    // Bail out after some time
    // g_timeout_add_seconds(600, callback, loop);

    // Start the mainloop
    g_main_loop_run(loop);

    // Clean up mainloop
    g_main_loop_unref(loop);

    // Disconnect from DBus
    g_dbus_connection_close_sync(dbusConnection, NULL, NULL);
    g_object_unref(dbusConnection);
    return 0;
}
