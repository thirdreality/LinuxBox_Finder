#!/usr/bin/python3
"""
HTTP Server for LinuxBox Finder that mirrors the functionality of the BLE GATT server.
This server runs when WiFi is connected and provides the same APIs as the BLE service.
"""

import json
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs
import os
import signal
import sys

from wifi_manager import WifiManager, WifiStatus

# Global WiFi manager instance
wifi_manager = None
server = None

class LinuxBoxHTTPHandler(BaseHTTPRequestHandler):
    """HTTP request handler for LinuxBox services"""
    
    def _set_headers(self, content_type="application/json"):
        self.send_response(200)
        self.send_header('Content-type', content_type)
        self.send_header('Access-Control-Allow-Origin', '*')  # Enable CORS
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Content-Type')
        self.end_headers()
    
    def do_OPTIONS(self):
        """Handle preflight requests for CORS"""
        self._set_headers()
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        # WiFi Status characteristic
        if path == "/api/wifi/status":
            self._handle_wifi_status()
        
        # System info characteristic
        elif path == "/api/system/info":
            self._handle_sys_info()
        
        # Handle unknown paths
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found"}).encode())
    
    def do_POST(self):
        """Handle POST requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        # Get content length
        content_length = int(self.headers['Content-Length']) if 'Content-Length' in self.headers else 0
        
        # Read request body
        post_data = self.rfile.read(content_length).decode('utf-8')
        
        # WiFi configuration characteristic
        if path == "/api/wifi/config":
            self._handle_wifi_config(post_data)
        
        # System command characteristic (write operation)
        elif path == "/api/system/command":
            self._handle_sys_command_write(post_data)
        
        # Handle unknown paths
        else:
            self.send_response(404)
            self.end_headers()
            self.wfile.write(json.dumps({"error": "Not found"}).encode())
    
    def _handle_wifi_status(self):
        """Handle GET /api/wifi/status - equivalent to WifiStatusCharacteristic"""
        global wifi_manager
        
        if wifi_manager:
            status = wifi_manager.get_status()
            result = {
                "connected": status.connected,
                "ssid": status.ssid,
                "ip_address": status.ip_address,
                "mac_address": status.mac_address,
                "error_message": status.error_message
            }
        else:
            result = {
                "connected": False,
                "ssid": "",
                "ip_address": "",
                "mac_address": "",
                "error_message": "WiFi manager not initialized"
            }
        
        self._set_headers()
        self.wfile.write(json.dumps(result).encode())
    
    def _handle_wifi_config(self, post_data):
        """Handle POST /api/wifi/config - equivalent to WIFIConfigCharacteristic"""
        global wifi_manager
        
        try:
            config = json.loads(post_data)
            
            if "ssid" in config:
                ssid = config["ssid"]
                password = config.get("password", "")
                
                if wifi_manager:
                    result = wifi_manager.configure(ssid, password)
                    response = {
                        "success": result == 0,
                        "message": f"WiFi configuration result: {result}"
                    }
                else:
                    response = {
                        "success": False,
                        "message": "WiFi manager not initialized"
                    }
            else:
                response = {
                    "success": False,
                    "message": "SSID is required"
                }
                
        except json.JSONDecodeError:
            response = {
                "success": False,
                "message": "Invalid JSON data"
            }
        except Exception as e:
            response = {
                "success": False,
                "message": f"Error processing WiFi config: {e}"
            }
        
        self._set_headers()
        self.wfile.write(json.dumps(response).encode())
    
    def _handle_sys_info(self):
        """Handle GET /api/system/info - equivalent to SysInfoCharacteristic"""
        import platform
        import psutil
        
        # Get system information
        system_info = {
            "hostname": platform.node(),
            "platform": platform.system(),
            "platform_version": platform.version(),
            "architecture": platform.machine(),
            "processor": platform.processor(),
            "cpu_count": psutil.cpu_count(),
            "cpu_percent": psutil.cpu_percent(),
            "memory_total": psutil.virtual_memory().total,
            "memory_available": psutil.virtual_memory().available,
            "disk_usage": dict(psutil.disk_usage('/').__dict__)
        }
        
        self._set_headers()
        self.wfile.write(json.dumps(system_info).encode())
    
    def _handle_sys_command_write(self, post_data):
        """Handle POST /api/system/command - equivalent to SysCommandCharacteristic.WriteValue"""
        global wifi_manager
        
        try:
            command_data = json.loads(post_data)
            command = command_data.get("command", "")
            
            if not command:
                response = {
                    "success": False,
                    "message": "Command is required"
                }
            else:
                # Execute the command using WiFi manager
                if wifi_manager:
                    result, status = wifi_manager.execute_command_with_response(command)
                    response = {
                        "success": status == 0,
                        "message": result
                    }
                else:
                    response = {
                        "success": False,
                        "message": "WiFi manager not initialized"
                    }
                
        except json.JSONDecodeError:
            response = {
                "success": False,
                "message": "Invalid JSON data"
            }
        except Exception as e:
            response = {
                "success": False,
                "message": f"Error processing command: {e}"
            }
        
        self._set_headers()
        self.wfile.write(json.dumps(response).encode())


def start_server(port=8086):
    """Start the HTTP server"""
    global server
    
    # 检查服务器是否已经在运行
    if server is not None:
        print(f"HTTP server already running on port {port}")
        return True
    
    try:
        server_address = ('', port)
        server = HTTPServer(server_address, LinuxBoxHTTPHandler)
        print(f"Starting HTTP server on port {port}")
        
        # Create a thread for the server
        server_thread = threading.Thread(target=server.serve_forever)
        server_thread.daemon = True
        server_thread.start()
        
        return True
    except Exception as e:
        print(f"Failed to start HTTP server: {e}")
        return False

def stop_server():
    """Stop the HTTP server"""
    global server
    
    if server:
        print("Stopping HTTP server")
        server.shutdown()
        server = None

def signal_handler(signum, frame):
    """Handle termination signals"""
    print(f"Received signal {signum}, exiting HTTP server gracefully...")
    stop_server()
    sys.exit(0)

def init(wifi_mgr):
    """Initialize the HTTP server with the WiFi manager"""
    global wifi_manager
    
    # Set WiFi manager
    wifi_manager = wifi_mgr
    
    # Start server
    return start_server()

if __name__ == "__main__":
    # Test the server directly
    wifi_mgr = WifiManager()
    wifi_mgr.init()
    
    # Define signal handlers for clean exit on termination signals
    signal.signal(signal.SIGTERM, signal_handler)
    signal.signal(signal.SIGINT, signal_handler)
    
    if init(wifi_mgr):
        try:
            # Keep the main thread alive
            while True:
                time.sleep(10)
        except KeyboardInterrupt:
            stop_server()
            wifi_mgr.cleanup()
            print("HTTP server stopped")
