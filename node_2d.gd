extends Control

# Network protocol used by Slippi:
# https://github.com/jordan-zilch/slippi-wiki/blob/master/SPECTATOR_PROTOCOL.md

# Binary payload format:
# https://github.com/project-slippi/slippi-wiki/blob/master/SPEC.md

# https://github.com/project-slippi/slippi-js/blob/efbafa721e272283a7924975f1dc8295ac522dac/src/console/types.ts#L19-L23
const SLIPPI_DEFAULT_PORT = 51441

var enet_connection := ENetConnection.new()
var enet_packet_peer: ENetPacketPeer
var handshake_sent := false

var event_payloads := PackedByteArray()

# Damage percentages of each player.
var player1_percentage := 0.0
var player2_percentage := 0.0
var player3_percentage := 0.0  # TODO: Support doubles (2v2)
var player4_percentage := 0.0  # TODO: Support doubles (2v2)

# Which controller port you're on (determines which hitsounds are played).
# TODO: Determine automatically based on player nametags. From my testing,
# this doesn't seem to be feasible for replays at least, as Game Start
# is never received by the client.
var port := 1

@onready var audio_stream_player := $AudioStreamPlayer as AudioStreamPlayer

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
								const FRAME_START_SIZE = 12 + 1
								const PERCENT_OFFSET = 0x3c
								var pl1 = payload.slice(FRAME_START_SIZE + PERCENT_OFFSET, FRAME_START_SIZE + PERCENT_OFFSET + 4)
								pl1.reverse()
								# Empirically determined by looking at the binary stream.
								const OFFSET_BETWEEN_PLAYERS = 0x41
								var pl2 = payload.slice(FRAME_START_SIZE + PERCENT_OFFSET + OFFSET_BETWEEN_PLAYERS, FRAME_START_SIZE + PERCENT_OFFSET + OFFSET_BETWEEN_PLAYERS + 4)
								pl2.reverse()
								var new_player1_percentage := pl1.decode_float(0)
								var new_player2_percentage := pl2.decode_float(0)

								if new_player1_percentage > player1_percentage:
									var damage_dealt := new_player1_percentage - player1_percentage
									if port == 2:
										audio_stream_player.pitch_scale = remap(damage_dealt, 0.0, 100.0, 1.0, 2.0)
										audio_stream_player.play()

								if new_player2_percentage > player2_percentage:
									var damage_dealt := new_player1_percentage - player1_percentage
									if port == 1:
										audio_stream_player.pitch_scale = remap(damage_dealt, 0.0, 100.0, 1.0, 2.0)
										audio_stream_player.play()

								player1_percentage = new_player1_percentage
								player2_percentage = new_player2_percentage
							0x3b:
								print("Item Update")
							0x3c:
								print("Frame Bookend")
							0x3d:
								print("Gecko List")
							0x10:
								print("Message Splitter")


func _exit_tree() -> void:
	print("Disconnecting...")
	enet_packet_peer.peer_disconnect()
