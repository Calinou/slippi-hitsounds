extends Node2D

# Network protocol used by Slippi:
# https:#github.com/jordan-zilch/slippi-wiki/blob/master/SPECTATOR_PROTOCOL.md

# Binary payload format:
# https:#github.com/project-slippi/slippi-wiki/blob/master/SPEC.md

# https:#github.com/project-slippi/slippi-js/blob/efbafa721e272283a7924975f1dc8295ac522dac/src/console/types.ts#L19-L23
const SLIPPI_DEFAULT_PORT = 51441

var enet_connection := ENetConnection.new()
var enet_packet_peer: ENetPacketPeer
var handshake_sent := false

var event_payloads := PackedByteArray()

func _ready() -> void:
	# Only 1 peer and 1 channel is needed (the running Dolphin Slippi instance).
	enet_connection.create_host(1)
	# FIXME: `localhost` doesn't work only `127.0.0.1` does.
	enet_packet_peer = enet_connection.connect_to_host("127.0.0.1", SLIPPI_DEFAULT_PORT)


# This method needs to run at 60 Hz to match the game's framerate.
func _physics_process(_delta: float) -> void:
	if not handshake_sent and enet_packet_peer.get_state() == ENetPacketPeer.STATE_CONNECTED:
		print("Sending handshake.")
		enet_packet_peer.send(
				0,
				'{ "type": "connect_request", "cursor": 0 }'.to_utf8_buffer(),
				ENetPacketPeer.FLAG_RELIABLE
		)
		handshake_sent = true

	var results := enet_connection.service()

	match results[0]:
		ENetConnection.EVENT_ERROR:
			push_error("An ENet error has occurred.")
		ENetConnection.EVENT_CONNECT:
			print("Peer connected.")
		ENetConnection.EVENT_DISCONNECT:
			push_error("Peer disconnected.")
		ENetConnection.EVENT_RECEIVE:
			var sent := enet_connection.pop_statistic(ENetConnection.HOST_TOTAL_SENT_PACKETS)
			var received := enet_connection.pop_statistic(ENetConnection.HOST_TOTAL_RECEIVED_PACKETS)
			if results[1] is ENetPacketPeer:
				var peer: ENetPacketPeer = results[1]
				if peer.get_available_packet_count() > 0:
					var packet = JSON.parse_string(peer.get_packet().get_string_from_utf8())
					if packet.has("payload"):
						var cursor: int = packet.cursor
						var next_cursor: int = packet.next_cursor
						var payload := Marshalls.base64_to_raw(packet.payload)
						match payload[0]:
							0x35:
								print("Event Payloads")
								event_payloads = payload.slice(0, payload[1] + 1)
								print(event_payloads)
							0x36:
								print("Game Start")
							0x37:
								print("Pre-Frame Update")
							0x38:
								print("Post-Frame Update")
							0x39:
								print("Game End")
							0x3a:
								# Find Item Updates in between.
								var post_frame_idx := 0
								const FRAME_START_SIZE = 12 + 1
								var pl = payload.slice(FRAME_START_SIZE + 0x3c, FRAME_START_SIZE + 0x3c + 5)
								#pl.reverse()
								print(pl.decode_float(0))
								const PRE_FRAME_SIZE = 64 + 1
								const ITEM_SIZE = 44 + 1
								var item_idx := payload.find(0x3b, FRAME_START_SIZE + PRE_FRAME_SIZE + PRE_FRAME_SIZE)
								if item_idx > 0:
									# Found an item find other items.
									while item_idx > 0:
										#print("item")
										item_idx = payload.find(0x3b, item_idx + ITEM_SIZE)

									post_frame_idx = item_idx + ITEM_SIZE
								else:
									#print("no item")
									post_frame_idx = FRAME_START_SIZE + PRE_FRAME_SIZE + PRE_FRAME_SIZE


								print(payload.hex_encode())
								#printt(post_frame_idx, payload[post_frame_idx])
								#print()

								var percent := payload.slice(post_frame_idx + 0x16, post_frame_idx + 0x16 + 5)
								# Data is big-endian, so reverse it before decoding it.
								percent.reverse()
								#printt("Percent P1:", percent.decode_float(0))
								#var idx2 := payload.find(0x38)
								#if idx2 > 0:
									#printt("Percent P2:", payload.decode_float(idx2 + 0x16))

							0x3b:
								print("Item Update")
							0x3c:
								print("Frame Bookend")
							0x3d:
								print("Gecko List")
							0x10:
								print("Message Splitter")

						if false and payload[0] == 0x38:
							printt("Post-frame percent:", payload.decode_float(0x16))


func _exit_tree() -> void:
	print("Disconnecting...")
	enet_packet_peer.peer_disconnect()


# https://github.com/project-slippi/slippi-js/blob/efbafa721e272283a7924975f1dc8295ac522dac/src/utils/slpReader.ts#L250-L324
#func parse_payload(payload: PackedByteArray) -> int:
	#var readPosition = startPos != null && startPos > 0 ? startPos : slpFile.rawDataPosition
	#var stopReadingAt = slpFile.rawDataPosition + slpFile.rawDataLength
#
	## Generate read buffers for each
	#var commandPayloadBuffers = mapValues(slpFile.messageSizes, (size) => new Uint8Array(size + 1))
	#var splitMessageBuffer = new Uint8Array(0)
#
	#var commandByteBuffer = new Uint8Array(1)
	#while readPosition < stopReadingAt:
		#readRef(ref, commandByteBuffer, 0, 1, readPosition)
		#var commandByte = (commandByteBuffer[0] as number) ?? 0
		#var buffer = commandPayloadBuffers[commandByte]
		#if buffer == null:
			## If we don't have an entry for this command, return false to indicate failed read.
			#return readPosition
#
#
		#if buffer.length > stopReadingAt - readPosition:
			#return readPosition
#
		#var advanceAmount = buffer.length
#
		#readRef(ref, buffer, 0, buffer.length, readPosition)
		#if commandByte === Command.SPLIT_MESSAGE:
		  ## Here we have a split message, we will collect data from them until the last
		  ## message of the list is received.
		  #var view = new DataView(buffer.buffer)
		  #var size = readUint16(view, 0x201) ?? 512
		  #var isLastMessage = readBool(view, 0x204)
		  #var internalCommand = readUint8(view, 0x203) ?? 0
#
		  ## If this is the first message, initialize the splitMessageBuffer
		  ## with the internal command byte because our parseMessage function
		  ## seems to expect a command byte at the start.
		  #if splitMessageBuffer.length === 0:
			#splitMessageBuffer = new Uint8Array(1)
			#splitMessageBuffer[0] = internalCommand
#
		  ## Collect new data into splitMessageBuffer.
		  #var appendBuf = buffer.slice(0x1, 0x1 + size)
		  #var mergedBuf = new Uint8Array(splitMessageBuffer.length + appendBuf.length)
		  #mergedBuf.set(splitMessageBuffer)
		  #mergedBuf.set(appendBuf, splitMessageBuffer.length)
		  #splitMessageBuffer = mergedBuf
#
		#if isLastMessage:
			#commandByte = splitMessageBuffer[0] ?? 0
			#buffer = splitMessageBuffer
			#splitMessageBuffer = new Uint8Array(0)
#
#
		#var parsedPayload = parseMessage(commandByte, buffer)
		#var shouldStop = callback(commandByte, parsedPayload, buffer)
		#if shouldStop:
		  #break
#
		#readPosition += advanceAmount
	  #}
#
	  #return readPosition
