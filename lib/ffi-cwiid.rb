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
    ffi_lib [File.dirname(__FILE__)+'/../vendor/cwiid/libcwiid/libwcwiid.so', 'libcwiid.so', 'libcwiid.so.0']

    require File.dirname(__FILE__)+'/cwiid-structs.rb'

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

    EmptyOnMesgCallback = Proc.new do |w_ptr, m_count, msg_ptr, time_ptr|
    end

    OnMesgCallback = Proc.new do |w_ptr, m_count, msg_ptr, time_ptr|
      ActiveWiimote.each { |w|
        if w.w_ptr == w_ptr
          m = CwiidMesg.new( msg_ptr )
          type = m[:type]

          case m[:type]
          when :CWIID_MESG_BTN
            btn    = m[:btn_mesg].values.last

            v = {
              btn_2:      (btn & BTN_2) != 0,
              btn_1:      (btn & BTN_1) != 0,
              btn_A:      (btn & BTN_A) != 0,
              btn_B:      (btn & BTN_B) != 0,
              btn_MINUS:  (btn & BTN_MINUS) != 0,
              btn_PLUS:   (btn & BTN_PLUS) != 0,
              btn_HOME:   (btn & BTN_HOME) != 0,
              btn_LEFT:   (btn & BTN_LEFT) != 0,
              btn_RIGHT:  (btn & BTN_RIGHT) != 0,
              btn_DOWN:   (btn & BTN_DOWN) != 0,
              btn_UP:     (btn & BTN_UP) != 0,
            }
          when :CWIID_MESG_ACC
            v = m[:acc_mesg][:acc]
          else
            v = nil
          end
          m    = nil

          w.msg_queue << [m_count, type, v]
          #break
        end
      }
    end

    attach_function :cwiid_enable,  [ :pointer, :uchar ], :int # *wiimote, flag
    attach_function :cwiid_disable, [ :pointer, :uchar ], :int # *wiimote, flag


    module_function
    ActiveWiimote = []
    def _create_wiimote(_wiimote)
      #Cwiid.cwiid_set_mesg_callback(_wiimote, OnMesgCallback)
      Cwiid.cwiid_set_mesg_callback(_wiimote, EmptyOnMesgCallback)

      ActiveWiimote << WiimoteState.new(_wiimote)
      ActiveWiimote.last
    end

    def open_wiimote
      bdaddr     = MemoryPointer.new(:uint, 18)

      if wiimote = cwiid_open(bdaddr, 0)
        unless wiimote.null?
	        # p "wiimote connected id: %s" % [ W.cwiid_get_id(wiimote) ]
	        _create_wiimote wiimote
        else
	        p 'no wiimotes found!'; nil
        end
      end
    ensure
      bdaddr.free unless bdaddr.null?
    end

    def get_bdinfo
      res = []
      ba_ptr     = MemoryPointer.new(:uint, 18)
      bdinfo_ptr = MemoryPointer.new(Bdinfo, 5) # max 5 find

      count = cwiid_get_bdinfo_array(-1, 2, -1, bdinfo_ptr, 0)
      count.times do |n|
        W.ba2str(bdinfo_ptr[n], ba_ptr)
        #p "device: %s" % [ ba_ptr.read_string ]
        res << ba_ptr.read_string
      end

      res
    ensure
      ba_ptr.free     unless ba_ptr.null?
      bdinfo_ptr.free unless bdinfo_ptr.null?
    end

    def str2ba_ptr(s)
      ba_p = MemoryPointer.new(:int, 18)
      str2ba(s.dup, ba_p)
      ba_p
    end

    ## onload: disable cwiid error handler
    cwiid_set_err nil
    ::W = FFI::Cwiid


    # autoload..
    #autoload :Wiimote, 'wiimote_state'

    class WiimoteState
      LED_MAP = [ 1, 2, 4, 8 ]
      CWIID_FLAG_MESG_IFC = 0x01
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

      attr_accessor :w_ptr, :led_state, :rpt_mode, :rumble_state, :w_state, :msg_queue
      def initialize(wiimote_p)
	      @w_ptr = wiimote_p
        @led_state, @rpt_mode, @rumble_state, @msg_cb = 0, 0, 0, false
        @msg_queue = []
      end

      def enable_callback
        @msg_cb = true
        Cwiid.cwiid_enable @w_ptr, CWIID_FLAG_MESG_IFC
      end

      def disable_callback
        @msg_cb = false
        Cwiid.cwiid_disable @w_ptr, CWIID_FLAG_MESG_IFC
      end

      def enable_button_msg
        enable_rpt :btn
      end

      def enable_rpt(key)
        if _rpt = RPT_MAP[key]
          set_mode _rpt
        end
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

      def query_state
        res = { connected: connected? }

        _states  = MemoryPointer.new(CwiidState, 2) # or MAX_WIIMOTES ?
        Cwiid.cwiid_get_state(@w_ptr, _states[0])
        _state = CwiidState.new _states[0]


        res[:rpt_mode] = []
        (_state[:rpt_mode] & RPT_MAP[:status]) != 0     && res[:rpt_mode] << :status
        (_state[:rpt_mode] & RPT_MAP[:btn]) != 0        && res[:rpt_mode] << :btn
        (_state[:rpt_mode] & RPT_MAP[:acc]) != 0        && res[:rpt_mode] << :acc
        (_state[:rpt_mode] & RPT_MAP[:nunchuk]) != 0    && res[:rpt_mode] << :nunchuk
        (_state[:rpt_mode] & RPT_MAP[:classic]) != 0    && res[:rpt_mode] << :classic
        (_state[:rpt_mode] & RPT_MAP[:balance]) != 0    && res[:rpt_mode] << :balance
        (_state[:rpt_mode] & RPT_MAP[:motionplus]) != 0 && res[:rpt_mode] << :motionplus

        res[:led] = [
          (_state[:led] & LED_MAP[0]) != 0  ,
          (_state[:led] & LED_MAP[1]) != 0  ,
          (_state[:led] & LED_MAP[2]) != 0  ,
          (_state[:led] & LED_MAP[3]) != 0  ,
        ]

        res[:rumble]  = _state[:rumble] & 1
        res[:battery] = _state[:battery]

        btn           = _state[:buttons]

        res[:buttons] = {
          btn_2:      (btn & BTN_2) != 0,
          btn_1:      (btn & BTN_1) != 0,
          btn_A:      (btn & BTN_A) != 0,
          btn_B:      (btn & BTN_B) != 0,
          btn_MINUS:  (btn & BTN_MINUS) != 0,
          btn_PLUS:   (btn & BTN_PLUS) != 0,
          btn_HOME:   (btn & BTN_HOME) != 0,
          btn_LEFT:   (btn & BTN_LEFT) != 0,
          btn_RIGHT:  (btn & BTN_RIGHT) != 0,
          btn_DOWN:   (btn & BTN_DOWN) != 0,
          btn_UP:     (btn & BTN_UP) != 0,
        }

        res
      ensure
        #p 'query_state: flush _states mem'
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

      def connected?; !@w_ptr.nil?; end
      def destroy;    close!;       end

      def close!
        unless @w_ptr.nil?
          p 'CwiidState clean: ptr, mem and state'
          Cwiid.cwiid_close @w_ptr
          p 'freeing now'
          begin
            @w_ptr.free
            #@w_ptr = nil
          rescue
            #p 'failed to free @w_ptr!'
          end
          #p ' (flushed)'; true
          true
        end
        # [wiimote, w_state, bdaddr].each(&:free)
      end
    end
  end
end

__END__

require 'eventmachine'
require 'bacon'
Bacon.summary_on_exit

EM.run do
  #EM::PeriodicTimer.new(2) { puts '----tick' }
  puts "\n--------------------------------------------------------------------"
  puts '-> NOTE: make sure your wiimote is disconnected and not listening'
  puts "--------------------------------------------------------------------\n"
  puts '    ------------------------------------'
  puts '    --> prepare to press 1+2 on wiimote'
  puts '    ------------------------------------'
  sleep 1.5
  puts "\n--------------------------------------- starting test suite  -------\n\n"


  $m = nil

  describe 'FFI::Cwiid#get_bdinfo #1' do
    it 'should not find wiimote (none available)' do
      info = FFI::Cwiid.get_bdinfo
      info.should.kind_of? Array
      info.size.should == 0
    end

  puts "\n\n    -------------------------------------"
  puts '    ---> press 1+2 on wiimote now!'
  puts "    -------------------------------------\n\n"
  sleep 2

    it 'should find wiimote (at least one available)' do
      info = FFI::Cwiid.get_bdinfo
      info.size.should >= 1
    end
  end


  $m = W.open_wiimote
  #p 'wiimote now connected'
  $m.enable_callback
  $m.enable_rpt :btn # enable button msgs
  #$m.enable_rpt :acc


  describe 'FFI::Cwiid #open_wiimote' do
    it 'test wiimote is connected' do
      FFI::Cwiid::ActiveWiimote.size.should == 1
      w = FFI::Cwiid::ActiveWiimote.first
      w.w_ptr.nil?.should == false
    end
  end



  describe 'FFI::Cwiid::WiimoteState' do
    @w = FFI::Cwiid::ActiveWiimote.first
    it 'is connected' do
      @w.connected?.should == true
    end

    it '#query_state' do
      res = @w.query_state
      res.should.kind_of? Hash
      res.keys.should == [:connected, :rpt_mode, :led, :rumble, :battery]
      res[:led].should.kind_of? Array
    end

    it 'leds should be off' do
      @w.query_state[:led].should == [ false, false, false, false ]
    end

    it 'rumble should be off' do
      @w.query_state[:rumble].should == 0
    end

    it 'button rpt_mode should be on' do
      @w.query_state[:rpt_mode].should == [:btn, :acc]
    end

    it 'set leds' do
      @w.query_state[:led].should == [ false, false, false, false ]
      @w.led 1
      @w.query_state[:led].should == [ true,  false, false, false ]
      @w.led 1
      @w.led 4
      @w.led 3
      @w.query_state[:led].should == [ false, false, true, true ]
      @w.led 4
      @w.led 3
      @w.query_state[:led].should == [ false, false, false, false ]
    end
  end

  #$m.enable_rpt :acc
  EM::PeriodicTimer.new(60.5) {
    if $m.msg_queue.size >= 1
      puts '---handle'
      p $m.msg_queue
      #$m.msg_queue.clear
    end
  }

  EM::PeriodicTimer.new(2.5) {
    @w = FFI::Cwiid::ActiveWiimote.first
    p @w.query_state
  }

  EM::Timer.new(60) {

    #$m.disable_callback
    p 'cb disabled'
    #EM.next_tick { $m.destroy; p 'm destroy' }
    EM.next_tick { EM.stop }
  }
end
