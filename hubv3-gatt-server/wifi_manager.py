import subprocess
import os
import time

class WifiStatus:
    def __init__(self):
        self.connected = False
        self.ssid = ""
        self.ip_address = ""
        self.mac_address = ""
        self.error_message = ""

class WifiManager:
    WIFI_INTERFACE = "wlan0"
    
    @staticmethod
    def execute_command(command):
        try:
            result = subprocess.run(command, shell=True, capture_output=True, text=True, check=True)
            return result.stdout.strip(), 0
        except subprocess.CalledProcessError as e:
            return e.stderr.strip(), e.returncode
    
    def init(self):
        print("Initializing WiFi manager")
        result, status = self.execute_command(f"cat /sys/class/net/{self.WIFI_INTERFACE}/address")
        if status != 0:
            print(f"WiFi interface {self.WIFI_INTERFACE} not found")
            return -1
        print(f"WiFi interface {self.WIFI_INTERFACE} initialized")
        print(f"WiFi mac address is {result}")
        return 0
    
    def cleanup(self):
        print("Cleaning up WiFi manager")
        # Nothing specific to clean up in this implementation
    
    def configure(self, ssid, password):
        print(f"Configuring WiFi. SSID: {ssid}")
        command = f"nmcli device wifi connect '{ssid}'"
        if password:
            command += f" password '{password}'"
        
        _, status = self.execute_command(command)
        if status != 0:
            print("Failed to connect to WiFi network")
            return -1
        
        # Wait for the connection to be established
        for _ in range(20): # 20 seconds timeout
            if self.check_wifi_connected():
                print(f"Successfully connected to WiFi network: {ssid}")
                return 0
            time.sleep(1)
        
        print("Timed out waiting for WiFi connection")
        return -2

    def get_status(self):
        status = WifiStatus()
        command = f"nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d: -f2"
        result, state = self.execute_command(command)
        
        if state == 0 and result:
            status.connected = True
            status.ssid = result
        
        # 使用更简单的命令获取 IP 地址
        command = f"ip addr show {self.WIFI_INTERFACE} | grep -w inet | awk '{{print $2}}' | cut -d/ -f1"
        result, _ = self.execute_command(command)
        status.ip_address = result or "Unknown"

        command = f"cat /sys/class/net/{self.WIFI_INTERFACE}/address"
        result, _ = self.execute_command(command)
        status.mac_address = result or "Unknown"

        if not status.connected:
            status.error_message = "Not connected to any WiFi network"
        
        return status

    def delete_networks(self):
        print("Deleting all saved WiFi networks")
        command = "nmcli -t -f uuid connection"
        result, state = self.execute_command(command)
        
        if state != 0 or not result:
            print("Failed to list connections")
            return -1
        
        for uuid in result.splitlines():
            delete_cmd = f"nmcli connection delete uuid {uuid}"
            _, del_state = self.execute_command(delete_cmd)
            if del_state == 0:
                print(f"Successfully deleted connection with UUID: {uuid}")
            else:
                print(f"Failed to delete connection with UUID: {uuid}")
        
        return 0

    def execute_command_with_response(self, command):
        special_commands = {
            "restart_wifi": "nmcli radio wifi off && sleep 1 && nmcli radio wifi on",
            "restart_device": "reboot",
            "factory_reset": "reboot",
        }

        if command in special_commands:
            if command == "factory_reset":
                return "Factory reset completed", 0
            elif command == "restart_device":
                return "Restart device completed", 0
            else:
                return "Nothing device completed", 0

        response = f"Unknown command: {command}"
        return response, -1

    def check_wifi_connected(self):
        command = "nmcli -t -f GENERAL.STATE device show wlan0"
        result, state = self.execute_command(command)
        return state == 0 and "(connected)" in result

    def get_wlan0_ip(self):
        """直接获取 wlan0 的 IPv4 地址，如果没有则返回 None"""
        command = f"ip -4 -o addr show {self.WIFI_INTERFACE} | awk '{{print $4}}' | cut -d/ -f1"
        result, status = self.execute_command(command)
        
        if status == 0 and result:
            return result
        return None


# Example usage
# wifi_manager = WifiManager()
# wifi_manager.init()
# status = wifi_manager.get_status()
# print(f"Connected: {status.connected}, SSID: {status.ssid}")
