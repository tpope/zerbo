class Zerbo

  class Error < RuntimeError
  end

  # Bind to a serial port.
  def self.connect(device='/dev/zeo')
    new(device)
  end

  attr_reader :device

  def initialize(device=nil)
    device ||= '/dev/zeo'
    if device.respond_to?(:read)
      @device = device
    else
      require 'serialport'
      @device = SerialPort.new(device, 38400)
      unless RUBY_PLATFORM =~ /darwin/
        @device.read_timeout = 0
      end
    end
    @callbacks = []
  end

  def next_packet
    true until read(1) == 'A'
    version = read(1)
    checksum, length, inverse = read(5).unpack('Cvv')
    raise Error, "Invalid length" unless length ^ inverse == 65535
    raise Error, "Unsupported version #{version}" unless version == '4'
    time, subtime, sequence = read(4).unpack('CvC')
    data = read(length)
    sum = 0
    data.each_byte do |b|
      sum += b
    end
    raise Error, "Invalid checksum" unless sum % 256 == checksum
    instantiate(time, subtime, sequence, data)
  end
  alias next next_packet

  def read(*args)
    device.read(*args)
  end
  protected :read

  def instantiate(time, subtime, sequence, data)
    type, rest = data.unpack('Ca*')
    if type.zero?
      type, rest = rest.unpack('Ca*')
    end
    klass = DATA_TYPE_CLASSES.detect {|c| c.id == type}
    klass.new(self, time, subtime, sequence, rest)
  end
  protected :instantiate

  def add_callback(klass = Object, &block)
    @callbacks << [klass, block]
    self
  end

  def on_event(&block)
    add_callback(Event, &block)
  end

  def on_sleep_stage(&block)
    add_callback(SleepStage, &block)
  end

  def run
    loop do
      packet = next_packet
      @callbacks.each do |(klass, block)|
        if packet.kind_of?(klass)
          block.call(packet)
        end
      end
    end
  end

  def inspect
    "#<#{self.class.inspect} #{device.inspect}>"
  end

  protected


  DATA_TYPE_CLASSES = []

  class Packet

    def self.inherited(klass)
      DATA_TYPE_CLASSES << klass
    end

    class <<self
      attr_accessor :id
    end

    attr_reader :owner, :type, :sequence, :data

    def type
      self.class.id
    end

    def initialize(owner, time, subtime, sequence, data)
      @owner = owner
      @sequence = sequence
      @data = data
    end

    def guess_length
      data.index('A')
    end

    def to_i
      if data.length == 2
        unpack('v').first
      elsif data.length == 4
        unpack('V').first
      else
        raise NotImplementedError
      end
    end

    def inspect
      format_inspect((to_i || data).inspect)
    end

    protected

    def unpack(arg)
      @data.unpack(arg)
    end

    def format_inspect(custom)
      "#<#{self.class.inspect}(#{sequence}) #{custom}>"
    end

  end

  class SliceEnd < Packet
    self.id = 0x02
  end

  class Version < Packet
    self.id = 0x03
  end

  class Waveform < Packet
    self.id = 0x80
    undef to_i

    def raw
      data.unpack('v128').map do |v|
        v > 0x7fff ? -0x10000 ^ v : v
      end
    end

    def filtered
      unless @filtered
        # blindly stolen from the Python library.
        filter = [
          0.0056, 0.0190, 0.0113, -0.0106, 0.0029, 0.0041,
          -0.0082, 0.0089, -0.0062, 0.0006, 0.0066, -0.0129,
          0.0157, -0.0127, 0.0035, 0.0102, -0.0244, 0.0336,
          -0.0323, 0.0168, 0.0136, -0.0555, 0.1020, -0.1446,
          0.1743, 0.8150, 0.1743, -0.1446, 0.1020, -0.0555,
          0.0136, 0.0168, -0.0323, 0.0336, -0.0244, 0.0102,
          0.0035, -0.0127, 0.0157, -0.0129, 0.0066, 0.0006,
          -0.0062, 0.0089, -0.0082, 0.0041, 0.0029, -0.0106,
          0.0113, 0.0190, 0.0056
        ]
        p = raw.length
        q = filter.length
        n = p + q - 1
        @filtered = []
        n.times do |k|
          t = 0
          lower = [0, k-(q-1)].max
          upper = [p-1, k].min
          lower.upto(upper) do |i|
            t = t + raw[i] * filter[k-i]
          end
          @filtered << (t*1e6).round/1e6
        end
      end
      @filtered
    end

    def to_a
      filtered[90...218]
    end

    def inspect
      format_inspect(raw.inspect[1..-2])
    end
  end

  class FrequencyBins < Packet
    self.id = 0x83
    undef to_i

    def to_a
      unpack('v7')
    end

    def inspect
      format_inspect(to_a.inspect[1..-2])
    end
  end

  class SQI < Packet
    self.id = 0x84
  end

  class ZeoTimeStamp < Packet
    self.id = 0x8a

    def to_time
      Time.at(to_i).utc
    end

    def to_s
      to_time.strftime('%Y-%m-%dT%H:%M:%S')
    end

    def inspect
      format_inspect(to_s)
    end
  end

  class Impedence < Packet
    self.id = 0x97
  end

  class BadSignal < Packet
    self.id = 0x9c

    def to_b
      !to_i.zero?
    end

    def inspect
      format_inspect(to_b)
    end
  end

  class SleepStage < Packet
    self.id = 0x9d

    LOOKUP = [
      'Undefined',
      'Awake',
      'REM',
      'Light',
      'Deep'
    ]

    def to_s
      LOOKUP[to_i]
    end

    def inspect
      format_inspect(to_s)
    end

    def awake?
      to_s == 'Awake'
    end

    def asleep?
      rem? || light? || deep?
    end

    def rem?
      to_s == 'REM'
    end

    def light?
      to_s == 'Light'
    end

    def deep?
      to_s == 'Deep'
    end
  end

  class Event < Packet
    self.id = 0x00
  end

  class NightStart < Event
    self.id = 0x05
  end

  class SleepOnset < Event
    self.id = 0x07
  end

  class HeadbandDocked < Event
    self.id = 0x0e
  end

  class HeadbandUnDocked < Event
    self.id = 0x0f
  end

  class AlarmOff < Event
    self.id = 0x10
  end

  class AlarmSnooze < Event
    self.id = 0x11
  end

  class AlarmPlay < Event
    self.id = 0x13
  end

  class NightEnd < Event
    self.id = 0x15
  end

  class NewHeadband < Event
    self.id = 0x24
  end

end
