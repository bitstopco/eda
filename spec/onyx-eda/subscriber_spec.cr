require "../spec_helper"
require "../events"

class SubscriberInvocationsHash
  getter hash = {
    SimpleSubscriber                     => 0,
    "AbstractSubscriber: UserEvent"      => 0,
    "AbstractSubscriber: Users::Deleted" => 0,
    ComplexSubscriber                    => 0,
  }

  class_getter class_instance = new

  def self.instance
    @@class_instance.hash
  end
end

class SimpleSubscriber
  include Onyx::EDA::Subscriber(SomeOtherEvent)

  def handle(event)
    x = event.foo
    SubscriberInvocationsHash.instance[SimpleSubscriber] += 1
  end
end

class AbstractSubscriber
  include Onyx::EDA::Subscriber(UserEvent)

  # Note that this method would not be called on Users::Deleted event,
  # it acts as a fallback method
  def handle(event : UserEvent)
    x = event.id
    SubscriberInvocationsHash.instance["AbstractSubscriber: UserEvent"] += 1
  end

  def handle(event : Users::Deleted)
    x = event.reason
    SubscriberInvocationsHash.instance["AbstractSubscriber: Users::Deleted"] += 1
  end
end

class ComplexSubscriber
  include Onyx::EDA::Subscriber(Users::Deleted)
  include Onyx::EDA::Subscriber(SomeOtherEvent)

  def handle(event)
    SubscriberInvocationsHash.instance[ComplexSubscriber] += 1
  end
end

channel = Onyx::EDA::Channel.new

describe Onyx::EDA::Subscriber do
  simple_subscriber = SimpleSubscriber.new(channel)
  abstract_subscriber = AbstractSubscriber.new(channel)
  complex_subscriber = ComplexSubscriber.new(channel)

  it do
    channel.emit(SomeOtherEvent.new("bar"))
    channel.emit(Users::Created.new(42))
    channel.emit(Users::Deleted.new(42, "baz"))

    sleep(0.1)

    SubscriberInvocationsHash.instance[SimpleSubscriber].should eq 1
    SubscriberInvocationsHash.instance["AbstractSubscriber: UserEvent"].should eq 1
    SubscriberInvocationsHash.instance["AbstractSubscriber: Users::Deleted"].should eq 1
    SubscriberInvocationsHash.instance[ComplexSubscriber].should eq 2
  end
end
