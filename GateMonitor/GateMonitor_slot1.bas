; GateMonitor_slot1.bas
; A remote LoRa farm gate monitor and movement detector.
; (Main slot).
; Written by Jotham Gates
; Created 31/12/2024 (based on the battery voltage monitor).
; Modified 31/12/2024
;
; https://github.com/jgOhYeah/Farm-PJON-LoRa-network
;
; FLASH MODES:
; Sleeping: One flash ~once per minute
; Actively listening: One flash every half second
; Cannot connect to LoRa module on start: Constant long flashes (on half second, off half second).
;
#SLOT 1
#NO_DATA ; EEPROM settings set when uploading slot 0

#INCLUDE "include/GateMonitorCommon.basinc"
#INCLUDE "include/symbols.basinc"
#INCLUDE "include/generated.basinc"
#DEFINE ENABLE_LORA_RECEIVE
#DEFINE ENABLE_PJON_RECEIVE
#DEFINE ENABLE_LORA_TRANSMIT
#DEFINE ENABLE_PJON_TRANSMIT
#DEFINE ENABLE_PJON_TX_ACK
#DEFINE ENABLE_PJON_TX_ACK_REPEATEDLY
#DEFINE DISABLE_LORA_SETUP

init:
	; Initial setup (need to have run slot 0 for radio init)
	setfreq m32
	;#sertxd(NAME, " ",    VERSION , " MAIN", cr,lf, "Jotham Gates, Compiled ", ppp_date_uk, cr, lf)
	
main:
	; Check if anything has changed since last time.
	tmpwd_l = GATE_PIN
	tmpwd_h = PIR_PIN
	if tmpwd_l != gate_state or tmpwd_h > movement_state then
		; Gate has been opened / shut or movement detected.
		gate_state = tmpwd_l
		movement_state = tmpwd_h
		;#sertxd("Gate / movement detected", cr, lf)

		; Send status with acknowledge.
		gosub prepare_status
		gosub end_pjon_packet_ack
		gosub check_send_rtrn
		gosub sleep_lora

		last_tx_interval = interval_count ; Reset interval as we just sent somthing.
	else
		movement_state =  tmpwd_h ; In case the movement sensor went back to not detected.
	endif

	; Send without acknowledge every so often.
	inc interval_count
	tmpwd_l = interval_count - last_tx_interval / 16
	if tmpwd_l > tx_intervals then
		; Ready to send.
		;#sertxd("Regular update required", cr, lf)
		gosub prepare_status
		gosub end_pjon_packet
		gosub check_send_rtrn
		last_tx_interval = interval_count ; Reset for start of next interval.
	endif

	; TODO: RX
	
	sleep 1 ; Wait for a while in low power mode before checking again.
	
	; ; Alternate between sleeping and receiving for a while
	; for interval_count = 1 to tx_intervals
	; 	gosub receive_mode ; Listen for 30s ; Stack is now at 8 for this branch. Cannot add any more levels to this branch.
	; 	gosub sleep_mode ; Sleep for 2.5m
	; next interval_count
	goto main

; receive_mode:
; 	; Go into listen mode
; 	; Listens for the designated time and handles incoming packets
; 	; Maximum stack depth used: 7

; 	pulsout LED_PIN, 10000
; 	;#sertxd("Entering receive mode", cr, lf)
; 	long_listen_time = 0 ; By default, listen for only a short while.
; 	gosub setup_lora_receive ; Stack depth 4
; 	start_time = time
; 	rtrn = time ; Start time for led flashing
; 	do
; 		; Handle packets arriving
; 		if LORA_RECEIVED then
; 			gosub read_pjon_packet ; Stack depth 4
; 			if rtrn != PJON_INVALID_PACKET then
; 				;#sertxd("Valid packet received", cr, lf)
; 				; Valid packet
; 				high LED_PIN
; 				; Processing and actions
; 				level = 0 ; Whether to send the status back and stay listening for a while after.
; 				do while rtrn > 0 ; rtrn is the length left
; 					mask = @bptrinc ; Field is stored in mask
; 					dec rtrn
; 					select mask
; 						case 0xC6 ; "F" | 0x80 ; Fence on and off
; 							; 1 byte, 0 for off, anything else for on.
; 							;#sertxd("Fence ")
; 							if rtrn > 0 then
; 								if @bptrinc = 0 then
; 									;#sertxd("Off", cr, lf)
; 									light_enable = 0
; 									low LIGHT_PIN
; 								else
; 									;#sertxd("On", cr, lf)
; 									light_enable = 1
; 									high LIGHT_PIN
; 								endif
; 								UPDATE_EEPROM(EEPROM_LIGHT_ENABLED, light_enable, tmpwd_l)
; 								dec rtrn
; 							endif
; 							level = 1
; 						case 0xF2 ; "r" | 0x80 ; Radio transmissions on and off
; 							; 1 byte, 0 for off, anything else for on.
; 							;#sertxd("Transmit ")
; 							if rtrn > 0 then
; 								if @bptrinc = 0 then
; 									;#sertxd("Off", cr, lf)
; 									transmit_enable = 0
; 								else
; 									;#sertxd("On", cr, lf)
; 									transmit_enable = 1
; 								endif
; 								UPDATE_EEPROM(EEPROM_TX_ENABLED, transmit_enable, tmpwd_l)
; 								dec rtrn
; 							endif
; 							level = 1
; 						case 201 ; "I" | 0x80 ; Interval between transmissions
; 							; 1 byte, number of blocks to skip between transmissions.
; 							;#sertxd("Transmit interval is ")
; 							if rtrn > 0 then
; 								if @bptr != 0 then
; 									tx_intervals = @bptrinc
; 									sertxd(#tx_intervals)
; 									;#sertxd(" *1.5 minutes", cr, lf)
; 									UPDATE_EEPROM(EEPROM_TX_INTERVALS, tx_intervals, tmpwd_l)
; 								else
; 									inc bptr
; 									;#sertxd("invalid. Ignoring", cr, lf)
; 								endif
; 								dec rtrn
; 							endif
; 							level = 1
; 						case 0xF3 ; "s" | 0x80 ; Request status, msb is high as it is an instruction
; 							; No payload.
; 							;#sertxd("Status", cr, lf)
; 							level = 1
; 						case 0xD8 ; "X" | 0x80 ; Reset
; 							if rtrn > 0 then
; 								if @bptrinc = RESET_CODE then
; 									;#sertxd("Resetting", cr, lf)
; 									reset
; 								else
; 									;#sertxd("Bad code", cr, lf)
; 								endif
; 								dec rtrn
; 							endif
; 							level = 1
; 						else
; 							; Something not recognised or implemented
; 							; NOTE: Should the rest of the packet be discarded to ensure any possible data of unkown length is not treated as a field?
; 							;#sertxd("Field ")
; 							sertxd(#mask)
; 							;#sertxd(" unkown", cr, lf)
; 					endselect
; 				loop

; 				; Send a message back if needed.
; 				if level = 1 then
; 					;#sertxd("Replying", cr, lf)
; 					nap 5 ; Wait for things to settle (576ms)
; 					gosub send_status ; Reply with the current settings if needed
; 					gosub setup_lora_receive ; Go back to listening
; 					; Am going to be in long receive mode, so due for a status message when we leave.
; 					interval_count = tx_intervals
; 					long_listen_time = 1 ; Stay in receive mode for a longer time to make it easier to send subsequent commands.

; 				endif

; 				low LED_PIN
; 				start_time = time ; Reset the time. ; NOTE Possible security risk of being able to keep the box in high power state?
; 				rtrn = time
; 			else
; 				;#sertxd("Invalid packet recieved. Ignoring", cr, lf)
; 			endif
; 		endif

; 		; Flash the LED every half second
; 		tmpwd = time - rtrn
; 		if tmpwd >= RECEIVE_FLASH_INT then
; 			if long_listen_time = 1 then
; 				high LED_PIN
; 				;#sertxd("Long listen time", cr, lf)
; 				low LED_PIN
; 			else
; 				pulsout LED_PIN, 10000
; 			endif
; 			rtrn = time
; 		endif
; 		; nap 2 ; Save some power hopefully

; 		; How long do we stay in listening mode?
; 		tmpwd = time - start_time
; 		if long_listen_time = 1 then
; 			paramwd = LISTEN_TIME_AWAKE
; 		else
; 			paramwd	= LISTEN_TIME_NORMAL
; 		endif
; 	loop while tmpwd < paramwd
; 	return

sleep_mode:
	; Go into power saving mode
	;#sertxd("Entering sleep mode", cr, lf)
	gosub sleep_lora
	low LED_PIN
	
	disablebod
	sleep SLEEP_TIME
	enablebod
	return

prepare_status:
	; Prepares a message to send the monitor's status, up to the call to finalise the packet.
	; This allows acknowledgement to be requested or left off.
	; Maximum stack depth used: 6
	high LED_PIN
	;#sertxd("Sending state", cr, lf)
	gosub begin_pjon_packet

	; Battery voltage
	@bptrinc = "V"
	gosub get_voltage
	sertxd(#rtrn)
	;#sertxd(" (*0.1) V", cr, lf)
	gosub add_word

	; Gate state
	;#sertxd("Gate: ")
	sertxd(#gate_state, cr, lf)
	@bptrinc = "g"
	@bptrinc = gate_state

	; Movement detected
	;#sertxd("Movement: ")
	sertxd(#movement_state, cr, lf)
	@bptrinc = "M"
	@bptrinc = movement_state

	; TX interval
	;#sertxd("TX Interval: ")
	sertxd(#tx_intervals, cr, lf)
	@bptrinc = "I"
	@bptrinc = tx_intervals

	param1 = UPRSTEAM_ADDRESS
	return

check_send_rtrn:
	; Checks the return value from a packet send. The purpose of this is to reset the system in the event of the
	; radio misbehaving.
	if rtrn = LORA_RADIO_FAIL then ; Something went wrong. Attempt to reinitialise the radio module.
		;#sertxd("LoRa dropped out.")
		for tmpwd = 0 to 15
			toggle LED_PIN
			pause 4000
		next tmpwd

		;#sertxd("Will reset and have another go.", cr, lf, cr, lf)
		reset
	elseif rtrn = PJON_INVALID_ACK then
		;#sertxd("Invalid acknowledgement.", cr, lf)
	endif
	low LED_PIN
	return

get_voltage:
	; Calculates the supply voltage in 0.1V steps (255 = 25.5V)
	; fvrsetup FVR2048 ; set FVR as 2.048V
	; adcconfig %011 ; set FVR as ADC Vref+, 0V Vref-
	; readadc10 BATTERY_PIN, rtrn
#IFDEF ENABLE_FVR
	fvrsetup FVR2048 ; set FVR as 2.048V
	adcconfig %011 ; set FVR as ADC Vref+, 0V Vref-
#ENDIF
	readadc10 BATTERY_PIN, rtrn ; Do it twice to try and avoid croos talk from the first reading
	rtrn = rtrn * CAL_BATT_NUMERATOR / CAL_BATT_DENOMINATOR
	return

; #IFDEF ENABLE_TEMP
; get_temperature: ; DS18B20
; 	; sertxd("Temp ADC: ",#rtrn)
; 	; Attempt to get two fairly close together readings (avoid the 51.1C issue / read errors hopefully).
; 	readtemp12 TEMPERATURE_PIN, rtrn
	
; 	; rtrn contains the temperature and both readings were close.
; 	; sertxd("Temp raw: ",#rtrn)
; 	tmpwd = rtrn & $8000 ; Is the most significant bit 1, indicating a negative?
; 	if tmpwd != 0 then
; 		; Negative, sign extend as needed.
; 		; Take the two's complement
; 		rtrn = NOT rtrn + 1

; 		; Scale as needed
; 		rtrn = rtrn * 5 / 8

; 		; Take the two's complement again to make negative.
; 		rtrn = NOT rtrn + 1
; 	else
; 		rtrn = rtrn * 5 / 8
; 	endif
; 	; sertxd(" Calc: ",#rtrn,cr,lf)
; 	return
; #ENDIF

add_word:
	; Adds a word to @bptr in little endian format.
	; rtrn contains the word to add (it is a word)
	@bptrinc = rtrn_l
	@bptrinc = rtrn_h
	return

; Libraries that will not be run first thing.
#INCLUDE "include/LoRa.basinc"
#INCLUDE "include/PJON.basinc"