package com.example.app

import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothServerSocket
import android.bluetooth.BluetoothSocket
import android.bluetooth.le.AdvertiseCallback
import android.bluetooth.le.AdvertiseData
import android.bluetooth.le.AdvertiseSettings
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.bluetooth.le.BluetoothLeAdvertiser
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.SharedPreferences
import android.os.Build
import android.os.Bundle
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
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val TAG = "ChatterBT"
    private val CHANNEL = "com.example.app/ble_advertiser"
    private val PREFS_NAME = "chatter_prefs"
    private val PREF_BROADCAST_ENABLED = "broadcast_enabled"

    // Chatter standard service UUIDs
    private val CHATTER_BLE_UUID = UUID.fromString("0000ff01-0000-1000-8000-00805f9b34fb")
    // Scan-response service data carrying the user's handle
    private val CHATTER_HANDLE_UUID = UUID.fromString("0000ff02-0000-1000-8000-00805f9b34fb")
    private val CHATTER_RFCOMM_UUID = UUID.fromString("fa87c0d0-afac-11de-8a39-0800200c9a66")
    // How long a sent message may wait for the peer's ack before the link is presumed dead
    private val ACK_TIMEOUT_MS = 4000L

    private var methodChannel: MethodChannel? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var advertiseCallback: AdvertiseCallback? = null
    private var isAdvertising = false
    private var advertisedPayload: String? = null // "peerId:psm" currently on air

    private var myPeerId: String = ""
    private var myNodeName: String = ""
    // This node's Wi-Fi multiaddrs, shared in the handshake so a Bluetooth peer
    // can move the conversation to Wi-Fi when both are on the same network
    private var myAddrs: List<String> = emptyList()

    // Server and client state. RFCOMM needs the peer's classic MAC, which Android
    // hides; the LE L2CAP server is reachable at the address seen in a BLE scan.
    private var rfcommServer: AcceptThread? = null
    private var l2capServer: AcceptThread? = null
    private var l2capPsm = 0
    private val connectedThreads = ConcurrentHashMap<String, ConnectedThread>()

    // Advertising and server sockets die with the adapter; restore them when it returns
    private val bluetoothStateReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            when (intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)) {
                BluetoothAdapter.STATE_TURNING_OFF, BluetoothAdapter.STATE_OFF -> {
                    isAdvertising = false
                    advertisedPayload = null
                    advertiseCallback = null
                    stopServers()
                }
                BluetoothAdapter.STATE_ON -> {
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val adapter = (getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter
                    if (adapter != null && myPeerId.isNotEmpty() && prefs.getBoolean(PREF_BROADCAST_ENABLED, true)) {
                        Log.i(TAG, "Bluetooth back on; restarting broadcast")
                        startBroadcast(adapter) { error, message ->
                            if (error != null) Log.w(TAG, "Broadcast restart failed: $message")
                        }
                    }
                }
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(bluetoothStateReceiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            registerReceiver(bluetoothStateReceiver, filter)
        }
    }

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

                "setLocalIdentity" -> {
                    // Identity sent in the handshake; needed even when not advertising
                    call.argument<String>("peerId")?.takeIf { it.isNotEmpty() }?.let { myPeerId = it }
                    call.argument<String>("name")?.takeIf { it.isNotEmpty() }?.let { myNodeName = it }
                    call.argument<List<String>>("addrs")?.let { myAddrs = it }
                    result.success(true)
                }

                "getBroadcastEnabled" -> {
                    // On by default: peers can only fall back to Bluetooth if they can find us
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    val enabled = prefs.getBoolean(PREF_BROADCAST_ENABLED, true)
                    result.success(enabled)
                }

                "startAdvertising" -> {
                    call.argument<String>("peerId")?.takeIf { it.isNotEmpty() }?.let { myPeerId = it }
                    myNodeName = call.argument<String>("name") ?: "Chatter"

                    if (adapter == null || !adapter.isEnabled) {
                        result.error("BLUETOOTH_DISABLED", "Bluetooth is not enabled", null)
                        return@setMethodCallHandler
                    }
                    if (myPeerId.isEmpty()) {
                        result.error("NO_IDENTITY", "Node peer ID is not known yet", null)
                        return@setMethodCallHandler
                    }

                    // Report the real outcome from AdvertiseCallback, not just that we asked
                    startBroadcast(adapter) { error, message ->
                        if (error == null) {
                            val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                            prefs.edit().putBoolean(PREF_BROADCAST_ENABLED, true).apply()
                            result.success(true)
                        } else {
                            result.error(error, message, null)
                        }
                    }
                }

                "stopAdvertising" -> {
                    // Update persistent broadcast preference
                    val prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                    prefs.edit().putBoolean(PREF_BROADCAST_ENABLED, false).apply()

                    stopAdvertisingInternal()
                    result.success(true)
                }

                "isAdvertising" -> {
                    result.success(isAdvertising)
                }

                "connectBluetooth" -> {
                    val targetAddress = call.argument<String>("address") ?: ""
                    // Full peer ID, or the prefix a peer puts in its BLE advertisement
                    val expectedPeerId = call.argument<String>("peerId") ?: ""
                    // L2CAP PSM from the peer's advertisement; 0 = RFCOMM (needs the real MAC)
                    val psm = call.argument<Int>("psm") ?: 0

                    if (adapter == null || !adapter.isEnabled) {
                        result.error("BLUETOOTH_DISABLED", "Bluetooth is disabled", null)
                        return@setMethodCallHandler
                    }

                    if (targetAddress.isEmpty()) {
                        result.error("INVALID_ADDRESS", "Bluetooth target address is empty", null)
                        return@setMethodCallHandler
                    }

                    // Check if already connected
                    if (connectedThreads.containsKey(targetAddress) ||
                        (expectedPeerId.isNotEmpty() && connectedThreads.values.any { it.remotePeerId.startsWith(expectedPeerId) })) {
                        result.success(true)
                        return@setMethodCallHandler
                    }

                    Thread {
                        try {
                            val device = adapter.getRemoteDevice(targetAddress)
                            try {
                                adapter.cancelDiscovery()
                            } catch (_: SecurityException) {}
                            val useL2cap = psm > 0 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q
                            val socket = if (useL2cap) {
                                Log.i(TAG, "Initiating LE L2CAP connection to $targetAddress (PSM $psm)...")
                                device.createInsecureL2capChannel(psm)
                            } else {
                                Log.i(TAG, "Initiating RFCOMM connection to $targetAddress...")
                                // Use Insecure RFCOMM to connect directly without OS PIN dialogs
                                device.createInsecureRfcommSocketToServiceRecord(CHATTER_RFCOMM_UUID)
                            }
                            socket.connect()
                            Log.i(TAG, "Connected ${if (useL2cap) "L2CAP" else "RFCOMM"} socket to $targetAddress")

                            val conn = ConnectedThread(socket, targetAddress, outgoing = true)
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

                    if (targetConn == null) {
                        result.error("NOT_CONNECTED", "Peer $peerId is not connected via Bluetooth", null)
                        return@setMethodCallHandler
                    }

                    // Socket writes can block; keep them off the UI thread
                    val conn = targetConn
                    Thread {
                        val sent = conn.sendMessage(content)
                        runOnUiThread {
                            if (sent) {
                                result.success(true)
                            } else {
                                result.error("SEND_FAILED", "Bluetooth write to $peerId failed", null)
                            }
                        }
                    }.start()
                }

                "getConnectedBluetoothPeers" -> {
                    val peersList = ArrayList<Map<String, String>>()
                    // Each connection is indexed under both peerId and address
                    for (conn in connectedThreads.values.toSet()) {
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

                "showMessageNotification" -> {
                    showMessageNotification(
                        call.argument<String>("peerId") ?: "",
                        call.argument<String>("title") ?: "Chatter",
                        call.argument<String>("body") ?: "",
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    // One notification per conversation (tagged by peer ID), replaced by the
    // newest message; tapping it brings the app back.
    private fun showMessageNotification(peerId: String, title: String, body: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel("messages", "Messages", NotificationManager.IMPORTANCE_HIGH)
            )
        }
        val open = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, "messages")
        } else {
            @Suppress("DEPRECATION") Notification.Builder(this)
        }
        val notification = builder
            .setSmallIcon(R.drawable.ic_notification)
            .setColor(0xFFFFB547.toInt())
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(Notification.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(open)
            .build()
        try {
            manager.notify(peerId, 1, notification)
        } catch (e: SecurityException) {
            Log.w(TAG, "Notifications not allowed: ${e.message}")
        }
    }

    private fun startRfcommServer(adapter: BluetoothAdapter) {
        if (rfcommServer != null) return
        try {
            val server = adapter.listenUsingInsecureRfcommWithServiceRecord("ChatterMesh", CHATTER_RFCOMM_UUID)
            rfcommServer = AcceptThread(server, "RFCOMM").also { it.start() }
            Log.i(TAG, "Chatter RFCOMM server listening on $CHATTER_RFCOMM_UUID")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start RFCOMM server: $e")
        }
    }

    // Returns the PSM peers must dial, or 0 if LE L2CAP is unavailable (Android < 10)
    private fun startL2capServer(adapter: BluetoothAdapter): Int {
        if (l2capServer != null) return l2capPsm
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return 0
        return try {
            val server = adapter.listenUsingInsecureL2capChannel()
            l2capPsm = server.psm
            l2capServer = AcceptThread(server, "L2CAP").also { it.start() }
            Log.i(TAG, "Chatter L2CAP server listening on PSM $l2capPsm")
            l2capPsm
        } catch (e: Exception) {
            Log.e(TAG, "Failed to start L2CAP server: $e")
            0
        }
    }

    private fun stopServers() {
        rfcommServer?.cancel()
        rfcommServer = null
        l2capServer?.cancel()
        l2capServer = null
        l2capPsm = 0
    }

    // Starts the listeners and (re)starts advertising so the payload carries the
    // current PSM. onDone(errorCode, message) runs once; errorCode null = success.
    private fun startBroadcast(adapter: BluetoothAdapter, onDone: (String?, String?) -> Unit) {
        startRfcommServer(adapter)
        val psm = startL2capServer(adapter)

        val adv = adapter.bluetoothLeAdvertiser
        if (adv == null) {
            onDone("NOT_SUPPORTED", "BLE Advertising not supported on this device")
            return
        }

        val payloadKey = "$myPeerId:$psm:$myNodeName"
        if (isAdvertising && advertisedPayload == payloadKey) {
            onDone(null, null)
            return
        }
        stopAdvertisingInternal()

        val settings = AdvertiseSettings.Builder()
            .setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY)
            .setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_HIGH)
            .setConnectable(true)
            .setTimeout(0)
            .build()

        val pUuid = ParcelUuid(CHATTER_BLE_UUID)

        // Service data: [version 1][PSM hi][PSM lo][peer ID prefix]. Primary packet
        // total is 14 + 16 = 30 of the 31 allowed bytes. Every peer ID starts with
        // "12D3KooW", so the prefix carries 8 distinguishing characters.
        val serviceData = byteArrayOf(1, (psm shr 8).toByte(), psm.toByte()) +
            myPeerId.take(16).toByteArray(Charsets.UTF_8)
        val data = AdvertiseData.Builder()
            .setIncludeDeviceName(false)
            .setIncludeTxPowerLevel(false)
            .addServiceUuid(pUuid)
            .addServiceData(pUuid, serviceData)
            .build()

        // Scan response: the user's handle, so nearby phones can show who this is.
        // Anything longer than the 31-byte packet allows fails the whole
        // advertisement with ADVERTISE_FAILED_DATA_TOO_LARGE, so cap its size.
        val handleBytes = utf8Prefix(myNodeName, 20)
        val scanResponse = if (handleBytes.isNotEmpty()) {
            AdvertiseData.Builder()
                .addServiceData(ParcelUuid(CHATTER_HANDLE_UUID), handleBytes)
                .build()
        } else {
            val nameFits = (adapter.name ?: "").toByteArray(Charsets.UTF_8).size <= 26
            AdvertiseData.Builder()
                .setIncludeDeviceName(nameFits)
                .build()
        }

        val done = AtomicBoolean(false)
        val callback = object : AdvertiseCallback() {
            override fun onStartSuccess(settingsInEffect: AdvertiseSettings?) {
                Log.i(TAG, "BLE Advertising started for peer $myPeerId (L2CAP PSM $psm)")
                isAdvertising = true
                advertisedPayload = payloadKey
                if (done.compareAndSet(false, true)) onDone(null, null)
            }

            override fun onStartFailure(errorCode: Int) {
                Log.e(TAG, "BLE Advertising failed with error code: $errorCode")
                isAdvertising = false
                advertisedPayload = null
                if (done.compareAndSet(false, true)) onDone("ADVERTISE_FAILED", "BLE advertising failed (error $errorCode)")
            }
        }

        advertiser = adv
        advertiseCallback = callback
        try {
            adv.startAdvertising(settings, data, scanResponse, callback)
        } catch (e: Exception) {
            Log.e(TAG, "startAdvertising exception: $e")
            advertiseCallback = null
            if (done.compareAndSet(false, true)) onDone("ADVERTISE_ERROR", e.message)
        }
    }

    // Longest prefix of s that fits in maxBytes of UTF-8 without splitting a character
    private fun utf8Prefix(s: String, maxBytes: Int): ByteArray {
        var out = s
        while (out.toByteArray(Charsets.UTF_8).size > maxBytes) out = out.dropLast(1)
        return out.toByteArray(Charsets.UTF_8)
    }

    private fun stopAdvertisingInternal() {
        try {
            val cb = advertiseCallback
            if (cb != null) advertiser?.stopAdvertising(cb)
        } catch (e: Exception) {
            Log.w(TAG, "stopAdvertising exception: $e")
        }
        isAdvertising = false
        advertisedPayload = null
        advertiseCallback = null
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(bluetoothStateReceiver)
        } catch (_: Exception) {}
        // Don't leave an advertisement pointing at server sockets that are about to close
        stopAdvertisingInternal()
        stopServers()
        for ((_, conn) in connectedThreads) {
            conn.cancel()
        }
        connectedThreads.clear()
        super.onDestroy()
    }

    // Server socket thread listening for incoming connections
    private inner class AcceptThread(
        private val serverSocket: BluetoothServerSocket,
        private val label: String
    ) : Thread() {
        @Volatile private var isRunning = true

        override fun run() {
            while (isRunning) {
                val socket: BluetoothSocket = try {
                    serverSocket.accept()
                } catch (e: Exception) {
                    // Socket closed or Bluetooth turned off: accept() would fail forever
                    if (isRunning) Log.w(TAG, "$label accept exception: $e")
                    break
                }

                val address = try { socket.remoteDevice.address } catch (_: Exception) { "" }
                Log.i(TAG, "Accepted incoming $label connection from $address")
                val conn = ConnectedThread(socket, address, outgoing = false)
                conn.start()
            }
            try {
                serverSocket.close()
            } catch (_: Exception) {}
            // Allow a fresh listener to be started next time
            runOnUiThread {
                if (rfcommServer === this) rfcommServer = null
                if (l2capServer === this) {
                    l2capServer = null
                    l2capPsm = 0
                }
            }
        }

        fun cancel() {
            isRunning = false
            try {
                serverSocket.close()
            } catch (_: Exception) {}
        }
    }

    // Manages an active Bluetooth connection
    private inner class ConnectedThread(
        private val socket: BluetoothSocket,
        val deviceAddress: String,
        val outgoing: Boolean
    ) : Thread() {
        private val reader = BufferedReader(InputStreamReader(socket.inputStream, Charsets.UTF_8))
        private val writer = PrintWriter(OutputStreamWriter(socket.outputStream, Charsets.UTF_8), true)

        var remotePeerId: String = ""
        var remoteName: String = "Chatter Peer"
        // Chosen by the dialing side and sent in its handshake, so both phones can
        // tell duplicate links apart and agree on which one to keep
        var linkId: String = if (outgoing) UUID.randomUUID().toString() else ""
        @Volatile private var isRunning = true
        private val closed = AtomicBoolean(false)

        // Same value on both ends of the link: dialer's peer ID, then link ID
        fun linkKey(): String = "${if (outgoing) myPeerId else remotePeerId}|$linkId"

        // Messages written but not yet acknowledged by the peer, by message ID
        private inner class PendingAck {
            val latch = java.util.concurrent.CountDownLatch(1)
            @Volatile var acked = false
        }
        private val pendingAcks = ConcurrentHashMap<String, PendingAck>()

        // PrintWriter never throws; checkError() flushes and reports a broken socket
        @Synchronized
        private fun writeLine(line: String): Boolean {
            writer.println(line)
            return !writer.checkError()
        }

        override fun run() {
            try {
                // Send our initial handshake
                val handshakeObj = JSONObject().apply {
                    put("type", "handshake")
                    put("peerId", myPeerId)
                    put("name", myNodeName.ifEmpty { "Chatter" })
                    put("addrs", org.json.JSONArray(myAddrs))
                    if (outgoing) put("linkId", linkId)
                }
                if (!writeLine(handshakeObj.toString())) {
                    Log.w(TAG, "Failed to send handshake to $deviceAddress")
                    return
                }

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
                                if (!outgoing) linkId = json.optString("linkId")

                                // Both phones may have dialed each other at once. Keep the
                                // link with the lower key (identical on both ends), close the other.
                                val existing = if (remotePeerId.isNotEmpty()) connectedThreads[remotePeerId] else null
                                if (existing != null && existing !== this && existing.isAlive &&
                                    existing.linkKey() <= linkKey()) {
                                    Log.i(TAG, "Closing duplicate link to $remotePeerId")
                                    return
                                }

                                if (remotePeerId.isNotEmpty()) {
                                    connectedThreads[remotePeerId] = this
                                }
                                if (deviceAddress.isNotEmpty()) {
                                    connectedThreads[deviceAddress] = this
                                }
                                // Registered first, so closing the replaced link reports no disconnect
                                if (existing != null && existing !== this) existing.cancel()

                                Log.i(TAG, "Handshake completed with peer $remotePeerId ($remoteName)")

                                val addrsJson = json.optJSONArray("addrs")
                                val remoteAddrs = ArrayList<String>()
                                if (addrsJson != null) {
                                    for (i in 0 until addrsJson.length()) {
                                        addrsJson.optString(i).takeIf { it.isNotEmpty() }?.let { remoteAddrs.add(it) }
                                    }
                                }

                                runOnUiThread {
                                    val args = HashMap<String, Any>()
                                    args["peerId"] = remotePeerId
                                    args["name"] = remoteName
                                    args["address"] = deviceAddress
                                    args["addrs"] = remoteAddrs
                                    methodChannel?.invokeMethod("onBluetoothPeerConnected", args)
                                }
                            }

                            "ack" -> {
                                pendingAcks[json.optString("msgId")]?.let {
                                    it.acked = true
                                    it.latch.countDown()
                                }
                            }

                            "msg" -> {
                                val content = json.optString("content")
                                // Sender may have had no identity yet; fall back to the key
                                // the peer was registered under in onBluetoothPeerConnected
                                val from = json.optString("from").ifEmpty {
                                    remotePeerId.ifEmpty { deviceAddress }
                                }
                                val timestamp = json.optString("timestamp", System.currentTimeMillis().toString())
                                val id = json.optInt("id", (System.currentTimeMillis() % 100000).toInt())

                                // Content is an opaque (signed) mesh frame for the Go node
                                Log.i(TAG, "Received Bluetooth frame from $from (${content.length} bytes)")

                                // Confirm receipt so the sender knows it can stop trying
                                json.optString("msgId").takeIf { it.isNotEmpty() }?.let { msgId ->
                                    writeLine(JSONObject().put("type", "ack").put("msgId", msgId).toString())
                                }

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

        // Blocks until the peer acknowledges the message (or ACK_TIMEOUT_MS passes)
        fun sendMessage(content: String): Boolean {
            val msgId = UUID.randomUUID().toString()
            val pending = PendingAck()
            pendingAcks[msgId] = pending
            return try {
                val msgObj = JSONObject().apply {
                    put("type", "msg")
                    put("msgId", msgId)
                    put("from", myPeerId)
                    put("content", content)
                    put("timestamp", System.currentTimeMillis().toString())
                    put("id", (System.currentTimeMillis() % 100000).toInt())
                }
                if (!writeLine(msgObj.toString())) {
                    Log.e(TAG, "Bluetooth write to $deviceAddress failed; closing connection")
                    cancel()
                    return false
                }
                // A successful write only means the bytes reached the local stack
                pending.latch.await(ACK_TIMEOUT_MS, java.util.concurrent.TimeUnit.MILLISECONDS)
                if (!pending.acked) {
                    Log.e(TAG, "No ack from $deviceAddress for message $msgId; closing connection")
                    cancel()
                }
                pending.acked
            } catch (e: Exception) {
                Log.e(TAG, "Error sending Bluetooth message: $e")
                false
            } finally {
                pendingAcks.remove(msgId)
            }
        }

        fun cancel() {
            if (!closed.compareAndSet(false, true)) return
            isRunning = false
            // Wake senders still waiting for an ack; their messages were not delivered
            for (pending in pendingAcks.values) pending.latch.countDown()
            try {
                // Only remove our own entries: a newer connection to the same peer
                // (e.g. both sides dialed at once) may have replaced them
                if (remotePeerId.isNotEmpty()) {
                    connectedThreads.remove(remotePeerId, this)
                }
                if (deviceAddress.isNotEmpty()) {
                    connectedThreads.remove(deviceAddress, this)
                }
                socket.close()
            } catch (_: Exception) {}

            runOnUiThread {
                if (remotePeerId.isNotEmpty() && !connectedThreads.containsKey(remotePeerId)) {
                    val args = HashMap<String, String>()
                    args["peerId"] = remotePeerId
                    methodChannel?.invokeMethod("onBluetoothPeerDisconnected", args)
                }
            }
        }
    }
}
