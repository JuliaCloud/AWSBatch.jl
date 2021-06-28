
struct ComputeEnvironment
    arn::String

    function ComputeEnvironment(ce::AbstractString; aws_config::AbstractAWSConfig=global_aws_config())
        arn = compute_environment_arn(ce; aws_config)
        arn === nothing && error("No compute environment ARN found for $ce")
        new(arn)
    end
end

Base.:(==)(a::ComputeEnvironment, b::ComputeEnvironment) = a.arn == b.arn

function describe(ce::ComputeEnvironment; aws_config::AbstractAWSConfig=global_aws_config())
    describe_compute_environment(ce; aws_config)
end
function max_vcpus(ce::ComputeEnvironment; aws_config::AbstractAWSConfig=global_aws_config())
    describe(ce; aws_config)["computeResources"]["maxvCpus"]
end

# TODO this probably is not done
"""
    create_compute_environment(name, type="container";
                               aws_config=global_aws_config())

Create a compute environment of type `type` with name `name`.
"""
function create_compute_environment(name::AbstractString;
                                    managed::Bool=false, resources::AbstractDict=Dict{String,String}(),
                                    aws_config::AbstractAWSConfig=global_aws_config())
    type = managed ? "MANAGED" : "UNMANAGED"
    return if isempty(resources)
        @mock Batch.create_compute_environment(name, type; aws_config=aws_config)
    else
        params = Dict("computeResources"=>resources)
        @mock Batch.create_compute_environment(name, type, params; aws_config=aws_config)
    end
end

function compute_environment_arn(ce::AbstractString; aws_config::AbstractAWSConfig=global_aws_config())
    startswith(ce, "arn:") && return ce
    json = describe_compute_environment(ce; aws_config)
    isempty(json) ? nothing : json["computeEnvironmentArn"]
end

function describe_compute_environment(ce::ComputeEnvironment;
                                      aws_config::AbstractAWSConfig=global_aws_config())
    describe_compute_environment(ce.arn; aws_config)
end

function describe_compute_environment(ce::AbstractString;
                                      aws_config::AbstractAWSConfig=global_aws_config())::OrderedDict
    json = @mock Batch.describe_compute_environments(Dict("computeEnvironments" => [ce]);
                                                     aws_config=aws_config)
    envs = json["computeEnvironments"]
    len = length(envs)::Int
    @assert len <= 1
    return len == 1 ? first(envs) : OrderedDict()
end
