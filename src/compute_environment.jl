using AWSSDK.Batch: describe_compute_environments

struct ComputeEnvironment
    arn::String

    function ComputeEnvironment(ce::AbstractString)
        arn = compute_environment_arn(ce)
        arn === nothing && error("No compute environment ARN found for $ce")
        new(arn)
    end
end

Base.:(==)(a::ComputeEnvironment, b::ComputeEnvironment) = a.arn == b.arn

describe(ce::ComputeEnvironment) = describe_compute_environment(ce)
max_vcpus(ce::ComputeEnvironment) = describe(ce)["computeResources"]["maxvCpus"]

function compute_environment_arn(ce::AbstractString)
    startswith(ce, "arn:") && return ce
    json = describe_compute_environment(ce)
    isempty(json) ? nothing : json["computeEnvironmentArn"]
end

describe_compute_environment(ce::ComputeEnvironment) = describe_compute_environment(ce.arn)

function describe_compute_environment(ce::AbstractString)::OrderedDict
    json = @mock describe_compute_environments(Dict("computeEnvironments" => [ce]))
    envs = json["computeEnvironments"]
    len = length(envs)::Int
    @assert len <= 1
    return len == 1 ? first(envs) : OrderedDict()
end
