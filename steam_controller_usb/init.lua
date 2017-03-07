require("bit")

-- Dissector Table for steam controller control packets
scPacketTable = DissectorTable.new("sc_packet.msgType", "Steam Controller Packet", ftypes.UINT8, base.HEX)
scConfigTable = DissectorTable.new("sc_config.configType", "Steam Controller Config", ftypes.UINT8, base.HEX) -- 0x87
scUpdateTable = DissectorTable.new("sc_update.stateType", "Steam Controller state update", ftypes.UINT8, base.HEX) --0x01

------------------------------------------------------
-- Wrapper (Control)
------------------------------------------------------

function sc_packet()
	local protocol = Proto("SC_MSG",  "Steam Controller packet")
	local msgTypeField = ProtoField.uint8("sc_packet.msgType", "Message type", base.HEX)
	local msgLengthField = ProtoField.uint8("sc_packet.msgLength", "Message length")

	protocol.fields = {
		msgTypeField,
		msgLengthField
	}

	function protocol.dissector(dataBuffer, pinfo, tree)
		pinfo.cols.protocol = "sc_set_report";
		
		local msgTypeBuf = dataBuffer(0,1)
		local msgLengthBuf = dataBuffer(1,1)
		local msgType = msgTypeBuf:uint()
		local msgLength = msgLengthBuf:uint()
		
		local subtree = tree:add(protocol,dataBuffer(0, 2 + msgLength))
		
		subtree:add(msgTypeField, msgTypeBuf)
		subtree:add(msgLengthField, msgLengthBuf)
		
		local packetDissector = scPacketTable:get_dissector(msgType)
		local msgBuffer = dataBuffer(2, msgLength):tvb()
		
		if packetDissector == nil then
			updatePinfo(pinfo, msgType)
			local undecodedEntry = subtree:add(msgBuffer(), "Unknown Steam Controller message")
			undecodedEntry:add_expert_info(PI_UNDECODED)
			
			return msgLength
		end
		
		local consumedBytes = packetDissector:call(msgBuffer, pinfo, subtree)
		local remaining = msgBuffer(consumedBytes)
		
		if remaining:len() ~= 0 then
			local remainingEntry = subtree:add(remaining, "Unknown extra bytes:", tostring(remaining:bytes()))
			remainingEntry:add_expert_info(PI_UNDECODED, PI_NOTE)
		end
		
	end
	
	-- Set this up so the control dissector can use it
	sc_packet_dissector = protocol.dissector
end

sc_packet()

------------------------------------------------------
-- Wrapper (Interrupt)
------------------------------------------------------

function sc_update()
	local protocol = Proto("SC_UPDATE",  "Steam Controller state upadte")
	local msgTypeField = ProtoField.uint8("sc_packet.msgType", "Message type", base.HEX)
	local updateTypeField = ProtoField.uint8("sc_update.msgType", "Update type", base.HEX)
	local updateLengthField = ProtoField.uint8("sc_update.msgLength", "Update length")

	protocol.fields = {
		msgTypeField,
		updateTypeField,
		updateLengthField
	}

	function protocol.dissector(dataBuffer, pinfo, tree)
		pinfo.cols.protocol = "sc_state_update";
		
		local msgTypeBuf = dataBuffer(0,1)
		local msgType = msgTypeBuf:uint()
		local updateTypeBuf = dataBuffer(2,1)
		local updateType = updateTypeBuf:uint()
		local updateLengthBuf = dataBuffer(3,1)
		local updateLength = updateLengthBuf:uint()
		
		if msgType ~= 0x01 then return -1 end -- Only 0x01 should be an interrupt
		
		local subtree = tree:add(protocol,dataBuffer(0, 4 + updateLength))
		
		subtree:add(msgTypeField, msgTypeBuf)
		subtree:add(updateTypeField, updateTypeBuf)
		subtree:add(updateLengthField, updateLengthBuf)
		
		local packetDissector = scUpdateTable:get_dissector(updateType)
		local updateBuffer = dataBuffer(4, updateLength):tvb()
		
		if packetDissector == nil then
			updatePinfo(pinfo, updateType)
			local undecodedEntry = subtree:add(updateBuffer(), "Unknown Steam Controller update message")
			undecodedEntry:add_expert_info(PI_UNDECODED)
			
			return updateBuffer:len()
		end
		
		local consumedBytes = packetDissector:call(updateBuffer, pinfo, subtree)
		local remaining = updateBuffer(consumedBytes)
		
		if remaining:len() ~= 0 then
			local remainingEntry = subtree:add(remaining, "Unknown extra bytes:", tostring(remaining:bytes()))
			remainingEntry:add_expert_info(PI_UNDECODED, PI_NOTE)
		end
		
	end
	
	-- Set this up so the control dissector can use it
	sc_update_dissector = protocol.dissector
end

sc_update()

------------------------------------------------------
-- Lookup table for built-in sound IDs
------------------------------------------------------

builtinSounds = {
	[0x00] = "Warm and happy",
	[0x01] = "Invader",
	[0x02] = "Controller confirmed",
	[0x03] = "Victory",
	[0x04] = "Rise and Shine",
	[0x05] = "Shorty",
	[0x06] = "Warm boot",
	[0x07] = "Next level",
	[0x08] = "Shake it off",
	[0x09] = "Access denied",
	[0x0a] = "Deactivate",
	[0x0b] = "Discovery",
	[0x0c] = "Triumph",
	[0x0d] = "The Mann"
}

function updatePinfo(pinfo, msgId)
	if (pinfo.curr_proto == "SC_MSG") then
		pinfo.cols.info = string.format("%s 0x%x", pinfo.curr_proto, msgId)
	else 
		pinfo.cols.info = string.format("%s (0x%x)", pinfo.curr_proto, msgId)
	end
end

------------------------------------------------------
-- Type 0x8f : Feedback
------------------------------------------------------

function sc_feedback(msgId)
	local protocol = Proto("feedback",  "Steam Controller feedback")

	local hapticId = ProtoField.uint8("sc_msg_feedback.hapticId", "Selected acuator")
	local hiPulseLength = ProtoField.uint16("sc_msg_feedback.hiPulseLength", "High pulse duration")
	local loPulseLength = ProtoField.uint16("sc_msg_feedback.loPulseLength", "Low pulse duration")
	local repeatCount = ProtoField.uint16("sc_msg_feedback.repeatCount", "Repetitions")

	protocol.fields = {
		hapticId,
		hiPulseLength,
		loPulseLength,
		repeatCount
	}

	function protocol.dissector(msgBuffer, pinfo, subtree)
		local hapticIdBuf = msgBuffer(0,1);
		local hiPulseLengthBuf = msgBuffer(1,2);
		local loPulseLengthBuf = msgBuffer(3,2);
		local repeatCountBuf = msgBuffer(5,2);
		
		if hapticIdBuf:uint() == 0 then hapticName = "LEFT"
		else hapticName = "RIGHT" end
		
		period = (hiPulseLengthBuf:uint() + loPulseLengthBuf:uint());
		if period ~= 0 then state = "AT " .. math.floor(1000000.0/period) .. " Hz"
		else state = "STOP" end
		
		updatePinfo(pinfo, msgId)
		pinfo.cols.info:append(": " .. hapticName .. " " .. state)
		
		subtree:add(hapticId, hapticIdBuf)
		subtree:add_le(hiPulseLength, hiPulseLengthBuf)
		subtree:add_le(loPulseLength, loPulseLengthBuf)
		subtree:add_le(repeatCount, repeatCountBuf)
		
		return 7
	end

	scPacketTable:add(msgId, protocol)
end

sc_feedback(0x8f)

------------------------------------------------------
-- Type 0x81 : Disable lizard mode
------------------------------------------------------

function sc_lizard_off(msgId)
	local protocol = Proto("lizard_off", "Steam Controller disable lizard mode")
					
	function protocol.dissector(msgBuffer, pinfo, subtree)
		updatePinfo(pinfo, msgId)

		return 0
	end
	
	scPacketTable:add(msgId, protocol)
end

sc_lizard_off(0x81)

------------------------------------------------------
-- Type 0x85 : Enable lizard mode
------------------------------------------------------

function sc_lizard_on(msgId)
	local protocol = Proto("lizard_on", "Steam Controller enable lizard mode")
					
	function protocol.dissector(msgBuffer, pinfo, subtree)
		updatePinfo(pinfo, msgId)

		return 0
	end

	scPacketTable:add(msgId, protocol)
end

sc_lizard_on(0x85)

------------------------------------------------------
-- Type 0xB6 : Play builtin sound
------------------------------------------------------

function sc_play_sound(msgId)
	local protocol = Proto("play_sound", "Steam Controller builtin sound")

	local soundIdField = ProtoField.uint8("sc_msg_feedback.soundId", "Sound Id")

	protocol.fields = { soundIdField }

	function protocol.dissector(msgBuffer, pinfo, subtree)
		local soundIdBuf = msgBuffer(0,1)
		local soundId = soundIdBuf:uint()
		
		subtree:add(soundIdField, soundIdBuf)

		local sound = builtinSounds[soundId] or "UNKNOWN";
		updatePinfo(pinfo, msgId)
		pinfo.cols.info:append(": " .. sound .. " (0x" .. tostring(soundIdBuf:bytes()) ..")")

		return 1
	end

	scPacketTable:add(msgId, protocol)
end

sc_play_sound(0xb6)

------------------------------------------------------
-- Type 0x87 : Configure
------------------------------------------------------

function sc_config(msgId)
	local protocol = Proto("config", "Steam controller configuration")

	local configTypeField = ProtoField.uint8("sc_msg_config.configType", "Configured field ID", base.HEX)

	protocol.fields = { configTypeField }

	function protocol.dissector(msgBuffer, pinfo, subtree)
		-- TODO : Actual error
		if msgBuffer:len() % 3 ~= 0 then return 0 end
		updatePinfo(pinfo, msgId)
		
		for i=0, msgBuffer:len()-3, 3 do
			local configBuffer = msgBuffer(i, 3)
			local configTypeBuf = configBuffer(0,1)
			local configType = configTypeBuf:uint()
			
			local configtree = subtree:add(protocol,configBuffer)
			configtree:add(configTypeField, configTypeBuf)
			
			local configDissector = scConfigTable:get_dissector(configType)
			
			if configDissector == nil then
				configtree:add_expert_info(PI_UNDECODED)
			else
				configDissector:call(configBuffer(1):tvb(), pinfo, configtree)
			end
		end
	end

	scPacketTable:add(msgId, protocol)
end

sc_config(0x87)

------------------------------------------------------
-- Configure 0x2d : LED control
------------------------------------------------------

function sc_config_led(confId)
	protocol = Proto("CONFIG_LED",  "Set led brightness")

	brightnessField = ProtoField.uint8("sc_config.led.brightness", "Led brightness", base.DEC)
	protocol.fields = {brightnessField}

	function protocol.dissector(configBuffer, pinfo, configtree)
		local brightnessBuf = configBuffer(0,1)
		configtree:add(brightnessField, brightnessBuf)	
		local brightness = brightnessBuf:uint()
		pinfo.cols.info:append(": " .. "LED TO " .. brightness .. "%")
	end
	
	scConfigTable:add(confId, protocol)
end

sc_config_led(0x2d)

------------------------------------------------------
-- Configure 0x30 : ???
------------------------------------------------------

-- Known configure signal (by groupings) :
-- 0x2d
-- 0x3a, 0x37, 0x36
-- 0x32, 0x18, 0x31, 0x08, 0x07
-- 0x30, 0x2e, 0x35, 0x34, 0x3b

------------------------------------------------------
-- USB Control transfer dissector (for the setup header)
------------------------------------------------------

sc_usb_setup = Proto("SC_USB_SETUP",  "USB Setup header")

transferTypeField = Field.new("usb.transfer_type")
urbTypeField = Field.new("usb.urb_type")

function sc_usb_setup.dissector(tvb, pinfo, tree)
	if tvb:len() == 0 then return false end
	
	-- myField() returns a FieldInfo object
	local transferType = transferTypeField().value
	local urbType = urbTypeField().value
	
	if transferType == 2 and urbType == 83 then
		-- Must be a control transfer, not an interrupt
		-- Must be of type "Submit", not "Complete"
	
		--bmRequestTypeBuf = tvb(0,1)
		local bRequestBuf = tvb(0,1)
		local wValueBuf = tvb(1,2)
		local wIndexBuf = tvb(3,2)
		local wLengthBuf = tvb(5,2)
		local dataBuffer = tvb(7):tvb()
	
		sc_packet_dissector:call(dataBuffer, pinfo, tree)
		return 7 + dataBuffer:len();
	elseif transferType == 1 and urbType == 67 then
		dataBuffer = tvb():tvb()
		sc_update_dissector:call(dataBuffer, pinfo, tree)
	end
	
	return 0
end

--Note that these only work if the device descriptors are present in the capture.
dTable = DissectorTable.get("usb.product")
dTable:add(0x28de1102,sc_usb_setup) --USB controller
dTable:add(0x28de1142,sc_usb_setup) --Dongle
