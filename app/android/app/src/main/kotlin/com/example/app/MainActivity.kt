package com.example.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.Context
import android.content.SharedPreferences
import android.os.ParcelUuid
import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.io.PrintWriter
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

class MainActivity : FlutterActivity() {
    private val TAG = "ChatterBT"
    private val CHANNEL = "com.example.app/ble_advertiser"
    private val PREFS_NAME = "chatter_prefs"
    private val PREF_BROADCAST_ENABLED = "broadcast_enabled"

    // Chatter standard service UUIDs
    private val CHATTER_BLE_UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb")
    private val CHATTER_RFCOMM_UUID = UUID.fromString("fa87c0d0-afac-11de-8a39-0800200c9a66")

    private var methodChannel: MethodChannel? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var isAdvertising = false

    private var myPeerId: String = ""
    private var myNodeName: String = ""

    // RFCOMM Server and client state
    private var serverThread: AcceptThread? = null
    private val connectedThreads = ConcurrentHashMap<String, ConnectedThread>()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel

        channel.setMethodCallHandler { call, result ->
            val bluetoothManager = getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
            val adapter = bluetoothManager?.adapter

            when (call.method) {
                "isSupported" -> {
                    val supported = adapter != null
                    result.success(supported)
                }

                "getDeviceBluetoothInfo" -> {
                    val info = HashMap<String, String>()
                    if (adapter != null) {
                        try {
                            info["name"] = adapter.name ?: "Chatter Device"
                            // In newer Android versions, getAddress() may return dummy 02:00:00:00:00:00
                            info["address"] = adapter.address ?: ""
                        } catch (e: Exception) {
                            Log.w(TAG, "Failed to get adapter info: $e")
                        }
                    }
                    result.success(info)
                }

                "getBroadcastEnabled" -> {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val enabled = prefs.getBoolean(PREF_BROADCAST_ENABLED, false)
                    result.success(enabled)
                }

                "startAdvertising" -> {
                    val peerId = call.argument<String>("peerId") ?: "chatter"
                    val address = call.argument<String>("address") ?: ""
                    val name = call.argument<String>("name") ?: "Chatter"

                    myPeerId = peerId
                    myNodeName = name

                    if (adapter == null || !adapter.isEnabled) {
                        result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
                        return@setMethodCallHandler
                    }

                    // Start RFCOMM server listener if not already running
                    startRfcommServer(adapter)

                    // Persist broadcast enabled setting
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putBoolean(PREF_BROADCAST_ENABLED, true).apply()

                    advertiser = adapter.bluetoothLeAdvertiser
                    if (advertiser == null) {
                        result.error("NOT_SUPPORTED", "BLE Advertising not supported on this device", null)
                        return@setMethodCallHandler
                    }

                    if (isAdvertising) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    val settings = AdvertiseSettings.Builder()
                        .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
                        .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
                        .setConnectable(true)
                        .setTimeout(0)
                        .build()

                    val pUuid = ParcelUuid(CHATTER_BLE_UUID)

                    // Keep primary AdvertiseData strictly under 31 bytes
                    val data = AdvertiseData.Builder()
                        .setIncludeDeviceName(false)
                        .setIncludeTxPowerLevel(false)
                        .addServiceUuid(pUuid)
                        .build()

                    // Put short identity in ScanResponse to avoid ADVERTISE_FAILED_DATA_TOO_LARGE
                    val shortId = if (peerId.length > 12) peerId.substring(0, 12) else peerId
                    val shortBytes = shortId.toByteArray(Charsets.UTF_8)

                    val scanResponse = AdvertiseData.Builder()
                        .setIncludeDeviceName(true)
                        .addServiceData(pUuid, shortBytes)
                        .build()

                    advertiseCallback = object : AdvertiseCallback() {
                        override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                            Log.i(TAG, "BLE Advertising started successfully for peer $peerId")
                            isAdvertising = true
                        }

                        override fun onStartFailure(errorCode: Int) {
                            Log.e(TAG, "BLE Advertising failed with error code: $errorCode")
                            isAdvertising = false
                        }
                    }

                    try {
                        advertiser?.startAdvertising(settings, data, scanResponse, advertiseCallback)
                        isAdvertising = true
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "startAdvertising exception: $e")
                        result.error("ADVERTISE_ERROR", e.message, null)
                    }
                }

                "stopAdvertising" -> {
                    // Update persistent broadcast preference
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putBoolean(PREF_BROADCAST_ENABLED, false).apply()

                    try {
                        if (advertiser != null && advertiseCallback != null) {
                            advertiser?.stopAdvertising(advertiseCallback)
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "stopAdvertising exception: $e")
                    }
                    isAdvertising = false
                    advertiseCallback = null
                    result.success(true)
                }

                "isAdvertising" -> {
                    result.success(isAdvertising)
                }

                "connectBluetooth" -> {
                    val targetAddress = call.argument<String>("address") ?: ""
                    val expectedPeerId = call.argument<String>("peerId") ?: ""

                    if (adapter == null || !adapter.isEnabled) {
                        result.error("BLUETOOTH_DISABLED", "Bluetooth is disabled", null)
                        return@setMethodCallHandler
                    }

                    if (targetAddress.isEmpty()) {
                        result.error("INVALID_ADDRESS", "Bluetooth target address is empty", null)
                        return@setMethodCallHandler
                    }

                    // Check if already connected
                    if (connectedThreads.containsKey(targetAddress) || (expectedPeerId.isNotEmpty() && connectedThreads.containsKey(expectedPeerId))) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            Log.i(TAG, "Initiating RFCOMM connection to $targetAddress...")
                            val device = adapter.getRemoteDevice(targetAddress)
                            // Use Insecure RFCOMM to connect directly without OS PIN dialogs
                            val socket = device.createInsecureRfcommSocketToServiceRecord(CHATTER_RFCOMM_UUID)
                            adapter.cancelDiscovery()
                            socket.connect()
                            Log.i(TAG, "Connected RFCOMM socket to $targetAddress")

                            val conn = ConnectedThread(socket, targetAddress)
                            conn.start()
                            runOnUiThread { result.success(true) }
                        } catch (e: Exception) {
                            Log.e(TAG, "Failed to connect to Bluetooth device $targetAddress: $e")
                            runOnUiThread {
                                result.error("CONNECT_FAILED", "Bluetooth connection failed: ${e.message}", null)
                            }
                        }
                    }.start()
                }

                "sendBluetoothMessage" -> {
                    val peerId = call.argument<String>("peerId") ?: ""
                    val content = call.argument<String>("content") ?: ""

                    var sent = false
                    // Search by peerId or device address
                    var targetConn = connectedThreads[peerId]
                    if (targetConn == null) {
                        for ((_, conn) in connectedThreads) {
                            if (conn.remotePeerId == peerId) {
                                targetConn = conn
                                break
                            }
                        }
                    }

                    if (targetConn != null) {
                        sent = targetConn.sendMessage(content)
                    }

                    if (sent) {
                        result.success(true)
                    } else {
                        result.error("NOT_CONNECTED", "Peer $peerId is not connected via Bluetooth", null)
                    }
                }

                "getConnectedBluetoothPeers" -> {
                    val peersList = ArrayList<Map<String, String>>()
                    for ((_, conn) in connectedThreads) {
                        val p = HashMap<String, String>()
                        p["peerId"] = conn.remotePeerId
                        p["name"] = conn.remoteName
                        p["address"] = conn.deviceAddress
                        peersList.add(p)
                    }
                    result.success(peersList)
                }

                "disconnectBluetooth" -> {
                    val peerId = call.argument<String>("peerId") ?: ""
                    val conn = connectedThreads.remove(peerId)
                    conn?.cancel()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startRfcommServer(adapter: BluetoothAdapter) {
        if (serverThread == null) {
            try {
                serverThread = AcceptThread(adapter)
                serverThread?.start()
                Log.i(TAG, "Chatter RFCOMM server listening on $CHATTER_RFCOMM_UUID")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to start RFCOMM server: $e")
            }
        }
    }

    override fun onDestroy() {
        serverThread?.cancel()
        for ((_, conn) in connectedThreads) {
            conn.cancel()
        }
        connectedThreads.clear()
        super.onDestroy()
    }

    // Server socket thread listening for incoming connections
    private inner class AcceptThread(private val adapter: BluetoothAdapter) : Thread() {
        private val serverSocket: BluetoothServerSocket? by lazy {
            try {
                adapter.listenUsingInsecureRfcommWithServiceRecord("ChatterMesh", CHATTER_RFCOMM_UUID)
            } catch (e: Exception) {
                Log.e(TAG, "listenUsingInsecureRfcomm failed: $e")
                null
            }
        }

        private var isRunning = true

        override fun run() {
            while (isRunning) {
                val socket: BluetoothSocket? = try {
                    serverSocket?.accept()
                } catch (e: Exception) {
                    if (isRunning) Log.w(TAG, "server accept exception: $e")
                    null
                }

                if (socket != null) {
                    val address = try { socket.remoteDevice.address } catch (_: Exception) { "" }
                    Log.i(TAG, "Accepted incoming Bluetooth connection from $address")
                    val conn = ConnectedThread(socket, address)
                    conn.start()
                }
            }
        }

        fun cancel() {
            isRunning = false
            try {
                serverSocket?.close()
            } catch (_: Exception) {}
        }
    }

    // Manages an active Bluetooth connection
    private inner class ConnectedThread(
        private val socket: BluetoothSocket,
        val deviceAddress: String
    ) : Thread() {
        private val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
        private val writer = PrintWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8), true)

        var remotePeerId: String = ""
        var remoteName: String = "Chatter Peer"
        private var isRunning = true

        override fun run() {
            try {
                // Send our initial handshake
                val handshakeObj = JSONObject().apply {
                    put("type", "handshake")
                    put("peerId", myPeerId)
                    put("name", myNodeName.ifEmpty { "Chatter" })
                }
                writer.println(handshakeObj.toString())

                while (isRunning) {
                    val line = reader.readLine() ?: break
                    if (line.trim().isEmpty()) continue

                    try {
                        val json = JSONObject(line)
                        val type = json.optString("type")

                        when (type) {
                            "handshake" -> {
                                remotePeerId = json.optString("peerId")
                                remoteName = json.optString("name", "Chatter Peer")

                                if (remotePeerId.isNotEmpty()) {
                                    connectedThreads[remotePeerId] = this
                                }
                                if (deviceAddress.isNotEmpty()) {
                                    connectedThreads[deviceAddress] = this
                                }

                                Log.i(TAG, "Handshake completed with peer $remotePeerId ($remoteName)")

                                runOnUiThread {
                                    val args = HashMap<String, Any>()
                                    args["peerId"] = remotePeerId
                                    args["name"] = remoteName
                                    args["address"] = deviceAddress
                                    methodChannel?.invokeMethod("onBluetoothPeerConnected", args)
                                }
                            }

                            "msg" -> {
                                val content = json.optString("content")
                                val from = json.optString("from", remotePeerId)
                                val timestamp = json.optString("timestamp", System.currentTimeMillis().toString())
                                val id = json.optInt("id", (System.currentTimeMillis() % 100000).toInt())

                                Log.i(TAG, "Received Bluetooth message from $from: $content")

                                runOnUiThread {
                                    val args = HashMap<String, Any>()
                                    args["from"] = from
                                    args["content"] = content
                                    args["timestamp"] = timestamp
                                    args["id"] = id
                                    methodChannel?.invokeMethod("onBluetoothMessageReceived", args)
                                }
                            }
                        }
                    } catch (e: Exception) {
                        Log.w(TAG, "Error parsing incoming Bluetooth line: $e")
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Connection lost with $deviceAddress: $e")
            } finally {
                cancel()
            }
        }

        fun sendMessage(content: String): Boolean {
            return try {
                val msgObj = JSONObject().apply {
                    put("type", "msg")
                    put("from", myPeerId)
                    put("content", content)
                    put("timestamp", System.currentTimeMillis().toString())
                    put("id", (System.currentTimeMillis() % 100000).toInt())
                }
                writer.println(msgObj.toString())
                true
            } catch (e: Exception) {
                Log.e(TAG, "Error sending Bluetooth message: $e")
                false
            }
        }

        fun cancel() {
            isRunning = false
            try {
                if (remotePeerId.isNotEmpty()) {
                    connectedThreads.remove(remotePeerId)
                }
                if (deviceAddress.isNotEmpty()) {
                    connectedThreads.remove(deviceAddress)
                }
                socket.close()
            } catch (_: Exception) {}

            runOnUiThread {
                if (remotePeerId.isNotEmpty()) {
                    val args = HashMap<String, String>()
                    args["peerId"] = remotePeerId
                    methodChannel?.invokeMethod("onBluetoothPeerDisconnected", args)
                }
            }
        }
    }
}
