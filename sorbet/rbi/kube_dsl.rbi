# typed: strict

module KubeDSL
  class DSLObject
    sig { returns(Resource) }
    def to_resource; end

    sig { returns(Symbol) }
    def kind_sym; end

    sig { returns(DSL::Meta::V1::ObjectMeta) }
    def metadata; end
  end

  class Resource
    sig { returns(String) }
    def to_yaml; end
  end

  module DSL
    module Meta
      module V1
        class ObjectMeta
          sig { params(args: String).returns(String) }
          def name(*args); end

          sig { params(args: String).returns(String) }
          def namespace(*args); end
        end
      end
    end
  end
end
