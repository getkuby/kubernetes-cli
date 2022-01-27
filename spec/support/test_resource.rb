# typed: true
require 'yaml'

class TestObject
  def initialize(object)
    @object = object
  end

  def to_resource
    TestResource.new(@object)
  end
end

class TestResource
  def initialize(object)
    @object = object
  end

  def to_yaml
    YAML.dump(@object)
  end
end
