require 'ffi'

# ffi-tk, Nicer introspection
class FFI::PrettyStruct < FFI::Struct
  def inspect
    kvs = members.zip(values)
    kvs.map!{|key, value| "%s=%s" % [key, value.inspect] }
    "<%s %s>" % [self.class, kvs.join(' ')]
  end
end


module FFI
module Cwiid
    extend FFI::Library
    ffi_lib 'libcwiid.so', 'libcwiid.so.0'

    require 'cwiid-structs'

    #
    # ATTACH_FUNCTIONS
    #
    BT_NO_WIIMOTE_FILTER = 0x01
    CWIID_LED1_ON	 = 0x01
    CWIID_LED2_ON	 = 0x02
    CWIID_LED3_ON	 = 0x04
    CWIID_LED4_ON	 = 0x08

    attach_function :cwiid_set_err, [ :pointer ], :void
    attach_function :cwiid_get_bdinfo_array, [ :int, :int, :int, :pointer, :int ], :int
    attach_function :ba2str, [ :pointer, :pointer ], :int
    attach_function :str2ba, [ :pointer, :pointer ], :int

    attach_function :cwiid_open, [:pointer, :int ], :pointer
    #attach_function :cwiid_open_timeout, [:pointer, :int, :timeout ], :pointer
    attach_function :cwiid_close, [:pointer ], :int
    attach_function :cwiid_get_id, [ :pointer ], :int

    attach_function :cwiid_set_led, [ :pointer, :uchar ], :int # *wiimote, led
    attach_function :cwiid_set_rumble, [ :pointer, :int ], :int # toggle_bit(rumble, 1);
    attach_function :cwiid_set_rpt_mode, [ :pointer, :uint8 ], :int
    attach_function :cwiid_get_state, [:pointer, CwiidState], :int
    #attach_function :cwiid_get_state, [:pointer, :pointer], :int

    callback :rb_cwiid_mcb, [ :pointer, :int, :pointer, :pointer ], :void
    attach_function :cwiid_set_mesg_callback, [:pointer, :rb_cwiid_mcb ], :int

    OnMesgCallback = Proc.new do |w_ptr, m_count, msg_ptr, time_ptr|
      #wiimote = SomeObjectCaste.new w_ptr
      p 'ON mesg callback! ..'
    end


    module_function
    ActiveWiimote = []
    def _create_wiimote(_wiimote)
      Cwiid.cwiid_set_mesg_callback(_wiimote, OnMesgCallback)

      $w = WiimoteState.new(_wiimote)
      ActiveWiimote << $w

      # enable 1st and 4th LED
      [1, 4].map {|i| $w.led i }

      #$w
      ActiveWiimote.last
    end

    def demo
      bdaddr     = MemoryPointer.new(:uint, 18)

      if wiimote = cwiid_open(bdaddr, 0)
        unless wiimote.null?
	        p wiimote
	        p "wiimote connected id: %s" % [ W.cwiid_get_id(wiimote) ]

	        _create_wiimote wiimote # returns WiimoteState.new
        else
	        p 'no wiimotes found!'; nil
        end
      end
    ensure
      bdaddr.free unless bdaddr.null?
    end



    def get_bdinfo
      ba_ptr     = MemoryPointer.new(:uint, 18)
      bdinfo_ptr = MemoryPointer.new(Bdinfo, 5) # max 5 find

      count = cwiid_get_bdinfo_array(-1, 2, -1, bdinfo_ptr, 0)

      if count >= 1;  p "found #{count} wiimotes!"
        count.times { |n|

          W.ba2str(bdinfo_ptr[n], ba_ptr)
	        p "device: %s" % [ ba_ptr.read_string ]
        }
      else
        p 'no wiimotes found!'; nil
      end
    ensure
      ba_ptr.free     unless ba_ptr.null?
      bdinfo_ptr.free unless bdinfo_ptr.null?
    end



    # toggle_bit shortcuts
    #def tb(bf, b); (bf & b) != 0 ? (bf & ~b) : (bf | b);  end
    def tb(bf, b); bf ^ b; end

    # bdaddr = str2ba_ptr('00:00:00:00:00:00') # 18 with \0 (unit? char?) int for now..
    def str2ba_ptr(s) # dear calller, dont forget to free it
      ba_p = MemoryPointer.new(:int, 18)
      str2ba(s.dup, ba_p)
      ba_p
    end


    ## onload: disable cwiid error handler
    cwiid_set_err nil
    ::W = FFI::Cwiid
    #::Wiid = FFI::Wiid


    # autoload..
    #autoload :Wiimote, 'wiimote_state'

    class WiimoteState
      LED_MAP = [ 1, 2, 4, 8 ]
      attr_accessor :w_ptr, :led_state, :rpt_mode, :rumble_state, :w_state
      def initialize(wiimote_p)
	      @w_ptr = wiimote_p
        @led_state, @rpt_mode, @rumble_state = 0, 0, 0
        # @w_state    = CwiidState.new
      end

      def led(index)
      	index = index - 1
      	return if index >= 4 #LED_MAP.size
      	set_led LED_MAP[index]
      end

      def rumble
        @rumble_state = (rumble_state == 0) ? 1 : 0
	      Cwiid.cwiid_set_rumble w_ptr, rumble_state
      end

      RPT_MAP = {
        :status  => 0x01,
        :btn     => 0x02,
        :acc     => 0x04,
        :ir      => 0x08,
        :nunchuk => 0x10,
        :classic => 0x20,
        :balance => 0x40,
        :motionplus => 128, # 0x80,
        :ext => 240 # (0x10 | 0x20 | 0x40 | 0x80),
      }

      def query_state
        puts "enter query_state.."
        #w_state = CwiidState.new
              _states  = MemoryPointer.new(CwiidState, 2) # or MAX_WIIMOTES ?

        #p w_state = _states[0]

        p 'do cwiid_get_state'
        #Cwiid.cwiid_get_state(@w_ptr, w_state)
        Cwiid.cwiid_get_state(@w_ptr, _states[0])

        p 'cast state..'
        #_state = CwiidState.new w_state
        _state = CwiidState.new _states[0]


        puts 'report mode:'
        p _state[:rpt_mode]
        p _state[:rpt_mode] & RPT_MAP[:status]
        p _state[:rpt_mode] & RPT_MAP[:btn]
        p _state[:rpt_mode] & RPT_MAP[:acc]
        p _state[:rpt_mode] & RPT_MAP[:nunchuk]
        p _state[:rpt_mode] & RPT_MAP[:classic]
        p _state[:rpt_mode] & RPT_MAP[:balance]
        p _state[:rpt_mode] & RPT_MAP[:motionplus]
        
        RPT_MAP.each {|k,v|
          p _state[:rpt_mode] & v
        }


        puts 'report leds:'
        p _state[:led] & LED_MAP[0]
        p _state[:led] & LED_MAP[1]
        p _state[:led] & LED_MAP[2]
        p _state[:led] & LED_MAP[3]

        LED_MAP.each {|v|
          p _state[:led] & v
        }


        puts 'report rumble:'
        p _state[:rumble] & 1

        puts 'report battery:'
        p _state[:battery]

        puts 'report buttons:'
        p _state[:buttons]

        p 'exit query_state'; true
            ensure
        p 'query_state: flush _states mem'
        w_state, _state = nil, nil
        _states.free
      end


      def set_led n
	      @led_state = (@led_state ^ n)
	      Cwiid.cwiid_set_led w_ptr, @led_state
      end

      def set_mode n
	      @rpt_mode = (@rpt_mode ^ n)
	      Cwiid.cwiid_set_rpt_mode w_ptr, @rpt_mode
      end

      def close!
        unless @w_ptr.nil?
          p 'CwiidState clean: ptr, mem and state'
          Cwiid.cwiid_close @w_ptr
          begin
            @w_ptr.free
            @w_ptr = nil
          rescue
                  p 'failed to free @w_ptr!'
          end
          p ' (flushed)'; true
        end
        # [wiimote, w_state, bdaddr].each(&:free)
      end
    end
  end
end


if $0 == __FILE__
  #p W.get_bdinfo
  p W.demo
end

