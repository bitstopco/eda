# A module which will make an object an event subscriber.
# A single object can have multiple `Subscriber` module included,
# just make sure you have `#handle` method defined for every event.
#
# A subscriber will subscribe itself on initialization by default
# and unsuscribe on finalization (i.e. implicitly).
#
# You can call `#subscribe` and `#unsubscribe` methods manually.
#
# NOTE: Don't forget to call `#subscribe` (or `super`) on custom initialization.
#
# ```
# class Reactor::AdminNotifier
#   include Onyx::EDA::Subscriber(Event::User::Registered)
#   include Onyx::EDA::Subscriber(Event::Payment::Successfull)
#
#   def initialize(channel : Onyx::EDA::Channel, @email_client : MyEmailClient)
#     super(channel)
#   end
#
#   def handle(event : Event::User::Registered)
#     @email_client.send("admin@example.com", "New user with id #{event.id}")
#   end
#
#   def handle(event : Event::Payment::Successfull)
#     @email_client.send("admin@example.com", "New payment of $#{event.amount}")
#   end
# end
#
# Reactor::AdminNotifier.new(channel)
# ```
module Onyx::EDA::Subscriber(T)
  # Handle incoming event. Must be defined explicitly in a subscriber.
  abstract def handle(event : T)

  @channel : Onyx::EDA::Channel

  # Calls `#subscribe` by default.
  def initialize(@channel : Onyx::EDA::Channel)
    subscribe
  end

  # Calls `#unsubscribe` by default.
  def finalize
    unsubscribe
  end

  # Subscribe to events calling `#handle`. It is defined on this module inclusion.
  # Raises if this subscriber is already called `#subscribe`.
  abstract def subscribe

  # Unsubscribe from events. It is defined on this module inclusion.
  # Raises if this subscriber is not subscribed yet or recently unsubscribed.
  abstract def unsubscribe

  @subscribed : Bool = false
  @procs : Hash(UInt64, Deque({Void*, Void*})) = Hash(UInt64, Deque({Void*, Void*})).new

  macro included
    def subscribe
      {% if @type.methods.find { |m| m.name == "subscribe" } %}
        previous_def
      {% else %}
        raise "Already subscribed" if @subscribed
        @subscribed = true
      {% end %}

      proc = @channel.subscribe(self, {{T}}) do |event|
        handle(event)
      end

      @procs[{{T}}.hash] ||= Deque({Void*, Void*}).new
      @procs[{{T}}.hash] << {proc.pointer, proc.closure_data}
    end

    def unsubscribe
      {% if @type.methods.find { |m| m.name == "unsubscribe" } %}
        previous_def
      {% else %}
        raise "Not subscribed yet. Must call `#subscribe` before unsubcribing" unless @subscribed
        @subscribed = false
      {% end %}

      deque = begin
        @procs[{{T}}.hash]
      rescue KeyError
        raise "Missing {{T}} procs in the internal Onyx::EDA::Subscriber hash"
      end

      while tuple = deque.shift?
        @channel.unsubscribe(self, {{T}}, &Proc({{T}}, Nil).new(tuple[0], tuple[1]))
      end
    end
  end
end
