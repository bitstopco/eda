# Extensions to default `Class` class.
class Class
  def to_redis_key : String
    {{@type.stringify.split("::").map(&.underscore).join("-")}}
  end
end
