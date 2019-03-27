require "../../spec_helper"
require "../../events"
require "../../../src/onyx-eda/channel/redis"

describe Onyx::EDA::Channel::Redis do
  channel = Onyx::EDA::Channel::Redis.new(ENV["REDIS_URL"])

  invocations_hash = {
    UserEvent          => 0,
    "AnotherUserEvent" => 0,
    Users::Deleted     => 0,
    SomeOtherEvent     => 0,
    Onyx::EDA::Event   => 0,
  }

  user_event_proc = ->(event : UserEvent) {
    a, b = event.class, event.id
    invocations_hash[UserEvent] += 1
  }

  channel.subscribe(Object, UserEvent, &user_event_proc)

  channel.subscribe(Object, UserEvent) do |event|
    a, b = event.class, event.id
    invocations_hash["AnotherUserEvent"] += 1
  end

  channel.subscribe(Object, SomeOtherEvent) do |event|
    a, b = event.class, event.foo
    invocations_hash[SomeOtherEvent] += 1
  end

  channel.subscribe(Object, Users::Deleted) do |event|
    a, b, c = event.class, event.id, event.reason
    invocations_hash[Users::Deleted] += 1
  end

  channel.subscribe(Object, Onyx::EDA::Event) do |event|
    a = event.class
    invocations_hash[Onyx::EDA::Event] += 1
  end

  describe "#emit" do
    it "returns events" do
      events = channel.emit(Users::Created.new(42))
      events.should be_a(Tuple(Users::Created))
      events.first.event_id.should be_a(UUID)
    end
  end

  sleep(0.1)

  describe "emitting Users::Created event" do
    it "invokes UserEvent subscription" do
      invocations_hash[UserEvent].should eq 1
    end

    it "invokes AnotherUserEvent subscription" do
      invocations_hash["AnotherUserEvent"].should eq 1
    end

    it "does not invoke Users::Deleted subscription" do
      invocations_hash[Users::Deleted].should eq 0
    end

    it "does not invoke SomeOtherEvent subscription" do
      invocations_hash[SomeOtherEvent].should eq 0
    end

    it "invokes Onyx::EDA::Event subscription" do
      invocations_hash[Onyx::EDA::Event].should eq 1
    end
  end

  describe "#emit with multiple events" do
    it "returns multiple events" do
      events = channel.emit(Users::Deleted.new(42, "migrated"), SomeOtherEvent.new("bar"))
      events.should be_a(Tuple(Users::Deleted, SomeOtherEvent))
      events.first.event_id.should be_a(UUID)
    end
  end

  sleep(0.1)

  describe "emitting Users::Deleted event" do
    it "does not invoke UserEvent subscription" do
      invocations_hash[UserEvent].should eq 2
    end

    it "does not invoke AnotherUserEvent subscription" do
      invocations_hash["AnotherUserEvent"].should eq 2
    end

    it "does not invoke Users::Deleted subscription" do
      invocations_hash[Users::Deleted].should eq 1
    end

    it "invokes SomeOtherEvent subscription" do
      invocations_hash[SomeOtherEvent].should eq 1
    end

    it "invokes Onyx::EDA::Event subscription" do
      invocations_hash[Onyx::EDA::Event].should eq 3
    end
  end

  describe "#unsubscribe" do
    it do
      channel.unsubscribe(Object, UserEvent).should eq(7)
    end

    it do
      channel.unsubscribe(Object).should eq(2)
    end
  end

  describe "#await" do
    it do
      spawn do
        channel.emit(Users::Created.new(42))
      end

      event = channel.await(Users::Created)
      event.id.should eq 42
    end

    context "with filter" do
      it do
        spawn do
          sleep(0.1)
          channel.emit(Users::Created.new(43))
        end

        event = channel.await(UserEvent, id: 43)
        event.id.should eq 43
      end
    end

    context "with block" do
      it do
        spawn do
          sleep(0.1)
          channel.emit(Users::Created.new(44))
        end

        id = channel.await(Users::Created, &.id)
        id.should eq 44
      end
    end

    context "with block and filter" do
      it do
        spawn do
          sleep(0.1)
          channel.emit(Users::Created.new(45))
        end

        id = channel.await(UserEvent, id: 45, &.id)
        id.should eq 45
      end
    end
  end
end
