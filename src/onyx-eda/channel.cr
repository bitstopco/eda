require "./event"

module Onyx::EDA
  # An in-memory event channel.
  # **Asynchronously** notifies all its subscribers on a new `Event`.
  #
  # ```
  # channel = Onyx::EDA::Channel.new
  # channel.subscribe(Object, MyEvent) { |e| pp e }
  # channel.emit(MyEvent.new)
  # sleep(0.01) # Need to yield the control, because all notifications are async
  # ```
  class Channel
    # Emit *events*, notifying all its subscribers (i.e. calling procs).
    # Procs are called asynchronously, therefore need to yield control after `#emit`.
    # Returns these events themselves.
    def emit(*events : *T) : T forall T
      emit(events)
    end

    # ditto
    def emit(events : Enumerable(T)) : Enumerable(T) forall T
      events.each do |event|
        notify(event)
      end

      events
    end

    # Subscribe an *object* to *event*, calling *proc* on event emit.
    # Immediately returns the given proc, which could be used on `#unsubscribe`.
    #
    # Channel distinguishes subscribers by their `object.hash`.
    # You can have a single object subscribed to multiple events with multiple procs.
    # You can specify an abstract object, as well as a module in addition to
    # standard class and struct as *event*.
    #
    # BUG: You currently can not pass a `Union` as an *event* argument.
    # Please use module or abstract object instead.
    #
    # ```
    # abstract struct AppEvent < Onyx::EDA::Event
    # end
    #
    # struct MyEvent < AppEvent
    #   getter foo
    #
    #   def initialize(@foo : String)
    #   end
    # end
    #
    # channel.subscribe(Object, AppEvent) do |event|
    #   pp event.foo
    # end
    #
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event.foo
    # end
    #
    # channel.emit(MyEvent.new("bar")) # Will print "bar" two times
    # ```
    #
    # You obviously can use it within objects as well:
    #
    # ```
    # class Notifier
    #   def initialize(channel)
    #     channel.subscribe(self, MyEvent) { }
    #   end
    #
    #   def stop
    #     channel.unsubscribe(self)
    #   end
    # end
    #
    # notifier = Notifier.new(channel)
    #
    # # ...
    #
    # channel.unsubscribe(notifier)
    # # Or
    # notifier.stop
    # ```
    def subscribe(object, event : T.class, &proc : T -> Nil) : Proc forall T
      add_subscription(object, event, &proc)
    end

    # Unsubscribe an *object* from *event* notifications by *proc*.
    # The mentioned proc will not be called again for this subscriber.
    #
    # NOTE: You should pass exactly the same proc object.
    # `ProcNotSubscribedError` is raised otherwise.
    # Returns number of unique unsubscribed procs.
    #
    # ```
    # proc = ->(e : MyEvent) { pp e }
    #
    # channel.subscribe(Object, MyEvent, &proc)
    #
    # # Would raise ProcNotSubscribedError
    # channel.unsubscribe(Object, MyEvent) do |e|
    #   pp e
    # end
    #
    # # OK
    # channel.unsubscribe(Object, MyEvent, &proc) # => {MyEvent => [proc]}
    # ```
    #
    # You can also make use of the fact that `#subscribe` returns a proc object:
    #
    # ```
    # proc = channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object, MyEvent, proc) # => {MyEvent => [proc]}
    # ```
    def unsubscribe(object, event : T.class, &proc : T -> Nil) : Int32 forall T
      remove_subscriptions(object, event, &proc)
    end

    # Unsubscribe an *object* from all *event* notifications.
    # Returns number of unique unsubscribed procs.
    #
    # ```
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object, AppEvent) # => {MyEvent => [#<Proc(MyEvent, Nil)>]}
    # ```
    def unsubscribe(object, event : T.class) : Int32 forall T
      remove_subscriptions(object, event)
    end

    # Unsubscribe an *object* from all events.
    # Returns number of unique unsubscribed procs.
    #
    # ```
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object) # => {MyEvent =>[#<Proc(MyEvent, Nil)>]}
    # ```
    def unsubscribe(object) : Int32
      remove_subscriptions(object)
    end

    @subscriptions : Hash(UInt64, Hash(UInt64, Set(Tuple(UInt64, Void*, Void*)))) = Hash(UInt64, Hash(UInt64, Set(Tuple(UInt64, Void*, Void*)))).new

    protected def add_subscription(object, event : T.class, &proc : T -> Nil) : Proc forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      tuple = {event.hash, proc.pointer, proc.closure_data}
      object_hash = object.hash

      {% for event_class in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? } %}
        unless hash = @subscriptions[{{event_class}}.hash]?
          hash = Hash(UInt64, Set(Tuple(UInt64, Void*, Void*))).new
          @subscriptions[{{event_class}}.hash] = hash
        end

        unless set = hash[object_hash]?
          set = Set(Tuple(UInt64, Void*, Void*)).new
          hash[object_hash] = set
        end

        set << tuple
      {% end %}

      return proc
    end

    protected def remove_subscriptions(
      object, event : T.class, &proc : T -> Nil
    ) : Int32 forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      tuple = {event.hash, proc.pointer, proc.closure_data}
      object_hash = object.hash
      removed_counter = 0

      {% for event_class in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? } %}
        if hash = @subscriptions[{{event_class}}.hash]?
          if proc_set = hash[object_hash]?
            if proc_set.includes?(tuple)
              proc_set.delete(tuple)
              removed_counter += 1

              if proc_set.empty?
                hash.delete(object_hash)
              end
            end
          end
        end
      {% end %}

      raise ProcNotSubscribedError.new(proc) unless removed_counter > 0
      return removed_counter
    end

    protected def remove_subscriptions(object, event : T.class) : Int32 forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      object_hash = object.hash
      removed_counter = 0

      {% for event_class in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? } %}
        if hash = @subscriptions[{{event_class}}.hash]?
          if proc_set = hash.delete(object_hash)
            removed_counter += proc_set.size
          end
        end
      {% end %}

      return removed_counter
    end

    protected def remove_subscriptions(object) : Int32
      object_hash = object.hash
      removed_counter = 0

      @subscriptions.each do |event_class_hash, hash|
        {% begin %}
          case event_class_hash
          {% for event_class in Object.all_subclasses.select { |t| t <= Onyx::EDA::Event && (t < Reference || t < Struct) && !t.abstract? } %}
            when {{event_class}}.hash
              if set = hash.delete(object_hash)
                removed_counter += set.size
              end
          {% end %}
          else
            raise "BUG: Hash didn't match any event class"
          end
        {% end %}
      end

      return removed_counter
    end

    protected def notify(event : T) : Nil forall T
      {%
        descendants = Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) && !t.abstract? }
        raise "#{T} has no descendants" if descendants.empty?
      %}

      {% for object in Object.all_subclasses.select { |t| t <= T && (t < Reference || t < Struct) } %}
        @subscriptions[{{object}}.hash]?.try do |hash|
          hash.each do |_, proc_set|
            proc_set.each do |(hash, pointer, closure_data)|
              {% begin %}
                case hash
                {% for type in (Class.all_subclasses.select { |t| t.instance >= T && !(t.instance <= Object) }.map(&.instance) + Object.all_subclasses.select { |t| t >= T && (t < Reference || t < Struct) }).uniq %}
                  when {{type}}.hash
                    spawn Proc({{type}}, Nil).new(pointer, closure_data).call(event.as({{type}}))
                {% end %}
                else
                  raise "BUG: Hash didn't match any event type"
                end
              {% end %}
            end
          end
        end
      {% end %}
    end

    # Cast UInt64 *hash* to an event type or raise.
    protected def hash_to_event_type(hash : UInt64)
      {% begin %}
        case hash
        {% for event_type in (Class.all_subclasses.select { |t| t.instance >= Onyx::EDA::Event && !(t.instance <= Object) }.map(&.instance) + Object.all_subclasses.select { |t| t <= Onyx::EDA::Event && (t < Reference || t < Struct) }).uniq %}
          when {{event_type}}.hash
            return {{event_type}}
        {% end %}
        else
          raise "BUG: Hash didn't match any event type"
        end
      {% end %}
    end

    # Raised if attempted to call [`Channel#unsubscribe(object, event, &proc`)](../Channel.html#unsubscribe%28object%2Cevent%3AT.class%2C%26proc%3AT-%3ENil%29%3AEnumerable%28String%29forallT-instance-method)
    # with a *proc*, which is not currently in the list of subscribers.
    #
    # Typical mistake:
    #
    # ```
    # channel.subscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    #
    # channel.unsubscribe(Object, MyEvent) do |event|
    #   pp event
    # end
    # ```
    #
    # The code above would raise, because these blocks result in two different procs.
    # Valid approach:
    #
    # ```
    # proc = ->(event : MyEvent) { pp event }
    # channel.subscribe(Object, MyEvent, &proc)
    # channel.unsubscribe(Object, MyEvent, &proc)
    # ```
    class ProcNotSubscribedError < Exception
      def initialize(proc)
        super("Proc #{proc} is not in the list of subscriptions. Make sure you're referencing the exact same proc")
      end
    end
  end
end
