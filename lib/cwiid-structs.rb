module FFI
module Cwiid

ENUM ||= {}
ENUM[:ext_types] = [
	:CWIID_EXT_NONE, 1,
	:CWIID_EXT_NUNCHUK,
	:CWIID_EXT_CLASSIC,
	:CWIID_EXT_BALANCE,
	:CWIID_EXT_MOTIONPLUS,
	:CWIID_EXT_UNKNOWN
]
ENUM[:cwiid_error] = [
	:CWIID_ERROR_NONE, 1, 
	:CWIID_ERROR_DISCONNECT,
	:CWIID_ERROR_COMM
]
ENUM[:cwiid_command] = [
	:CWIID_CMD_STATUS, 1,
	:CWIID_CMD_LED,
	:CWIID_CMD_RUMBLE,
	:CWIID_CMD_RPT_MODE
]
ENUM[:cwiid_mesg_type] = [
	:CWIID_MESG_STATUS, 0,
	:CWIID_MESG_BTN,
	:CWIID_MESG_ACC,
	:CWIID_MESG_IR,
	:CWIID_MESG_NUNCHUK,
	:CWIID_MESG_CLASSIC,
	:CWIID_MESG_BALANCE,
	:CWIID_MESG_MOTIONPLUS,
	:CWIID_MESG_ERROR,
	:CWIID_MESG_UNKNOWN
]

ExtType    = enum *ENUM[:ext_types]
MesgType   = enum *ENUM[:cwiid_mesg_type]
CwiidError = enum *ENUM[:cwiid_error]

#
# states structs
#
class NunchuckState < FFI::PrettyStruct
  layout :stick,        :uint8, 2,
         :acc,          :uint8, 3,
         :buttons,      :uint8, 
end

class ClassicState < FFI::PrettyStruct
  layout :l_stick,      :uint8, 2,
         :r_stick,      :uint8, 2,
         :l,            :uint8,
         :r,            :uint8,
         :buttons,      :uint16, 
end

class BalanceState < FFI::PrettyStruct
  layout :right_top,    :uint16, 
         :right_bottom, :uint16, 
         :left_top,     :uint16, 
         :left_bottom,  :uint16, 
end

class MotionplusState < FFI::PrettyStruct
  layout :angle_rate,   :uint16, 3
end

class ExtState < FFI::Union
  layout :nunchuck,    NunchuckState,
	 :classic,     ClassicState,
	 :balance,     BalanceState,
	 :motionplus,  MotionplusState,
end

#
# message structs
#
class StatusMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :battery,      :uint8, 
         :ext_type,     ExtType,
end

class BtnMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :buttons,      :uint16, 
end

class AccMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :acc,          :uint8, 3 
end

class IrSrc < FFI::Struct
  layout :valid,        :char, 
         :pos,          :uint16, 2,
         :size,         :uint8, 
end

class IrMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :src,          IrSrc, 4
end

class NunchukMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :stick,        :uint8, 2,
         :acc,          :uint8, 3,
	 :buttons,      :uint8
end

class ClassicMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :l_stick,      :uint8, 2,
         :r_stick,      :uint8, 2,
	 :l,            :uint8,
	 :r,            :uint8,
	 :buttons,      :uint16,
end

class BalanceMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :right_top,    :uint16, 
         :right_bottom, :uint16, 
         :left_top,     :uint16, 
         :left_bottom,  :uint16, 
end

class MotionplusMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :angle_rate,   :uint16, 3
end

class ErrorMesg < FFI::PrettyStruct
  layout :type,         MesgType,
         :error,        CwiidError
end

class CwiidMesg < FFI::Union
  layout :type,            MesgType,
	 :status_mesg,     StatusMesg,
	 :btn_mesg,        BtnMesg,
	 :acc_mesg,        AccMesg,
	 :ir_mesg,         IrMesg,
	 :nunchuk_mesg,    NunchukMesg,
	 :classic_mesg,    ClassicMesg,
	 :balance_mesg,    BalanceMesg,
	 :motionplus_mesg, MotionplusMesg,
	 :error_mesg,      ErrorMesg
end

class CwiidState < FFI::Struct
  layout :rpt_mode, :uint8, 
	 :led,      :uint8,
	 :rumble,   :uint8,
	 :battery,  :uint8,
	 :buttons,  :uint16,
	 :acc,      :uint8, 3,
	 :ir_src,   IrSrc, 4,
	 :ext_type, ExtType,
	 :ext,      ExtState,
	 :error,    CwiidError,
end

# cheap bdaddr inquery lookup, for lswm
class BdaddrT < FFI::Struct
  layout :b, :uint8, 6
end

class Bdinfo < FFI::PrettyStruct
  layout :bdaddr,  :pointer, 
	 :btclass, :uint8, 3,
         :name,    :string #, 32
end

  BTN_2		   = 0x0001
  BTN_1		   = 0x0002
  BTN_B		   = 0x0004
  BTN_A		   = 0x0008
  BTN_MINUS	 = 0x0010
  BTN_HOME	 = 0x0080
  BTN_LEFT	 = 0x0100
  BTN_RIGHT	 = 0x0200
  BTN_DOWN	 = 0x0400
  BTN_UP	   = 0x0800
  BTN_PLUS	 = 0x1000

end # Cwiid
end # FFI
