require 'bacon'
Bacon.summary_on_exit

describe 'FFI::Cwiid #toggle_bit' do
  #
  # cwiid.h:
  #  #define toggle_bit(bf,b) (bf) = ((bf) & b) ? ((bf) & ~(b)) : ((bf) | (b))
  #

  # first take
  def tb bf, b
    (bf & b) != 0 ? (bf & ~b) : (bf | b)
  end

  # sweet ruby!
  def tb bf, b
    bf ^ b
  end

  it 'should act on state and toggle bits' do
    #leds = [ 0x01, 0x02, 0x04, 0x08 ]
    leds = [ 1, 2, 4, 8 ]
    led_state = 0

    led_state = tb(led_state, leds[0])
    led_state = tb(led_state, leds[3])
    led_state.should == 9
    led_state = tb(led_state, leds[3])
    led_state.should == 1
    led_state = tb(led_state, leds[2])
    led_state.should == 5
    led_state = tb(led_state, leds[1])
    led_state.should == 7
    led_state = tb(led_state, leds[0])
    led_state.should == 6
  end
end

describe 'ruby: begin ensure' do
  it 'should call ensure but return begin' do
    c = nil
    Proc.new { begin; 1; ensure; c = 2; end; }.call.should == 1
    c.should == 2
  end
end
