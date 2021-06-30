"""
    LogEvent

A struct for representing an event in an AWS Batch job log.
"""
struct LogEvent
    id::String
    ingestion_time::DateTime  # in UTC
    timestamp::DateTime       # in UTC
    message::String
end

function Base.convert(::Type{LogEvent}, d::AbstractDict)
    LogEvent(
        d["eventId"],
        Dates.unix2datetime(d["ingestionTime"] / 1000),
        Dates.unix2datetime(d["timestamp"] / 1000),
        d["message"],
    )
end

function Base.print(io::IO, event::LogEvent)
    print(io, rpad(event.timestamp, 23), " ", event.message)
end

function Base.print(io::IO, log_events::Vector{LogEvent})
    for event in log_events
        println(io, event)
    end
end


"""
    log_events(log_group, log_stream) -> Union{Vector{LogEvent}, Nothing}

Fetches the CloudWatch log from the specified log group and stream as a `Vector` of
`LogEvent`s. If the log stream does not exist then `nothing` will be returned.
"""
function log_events(log_group::AbstractString, log_stream::AbstractString;
                    aws_config::AbstractAWSConfig=global_aws_config())
    events = LogEvent[]

    curr_token = nothing
    next_token = nothing

    # We've hit the end of the stream if the next token matches the current one.
    while next_token != curr_token || next_token === nothing
        response = try
            @mock Cloudwatch_Logs.get_log_events(
                log_group, log_stream,
                Dict("nextToken"=>next_token);
                aws_config=aws_config,
            )
        catch e
            # The specified log stream does not exist. Specifically, this can occur when
            # a batch job has a reference to a log stream but the stream has not yet been
            # created.
            if (
                e isa AWSExceptions.AWSException &&
                e.cause.status == 400 &&
                e.info["message"] == "The specified log stream does not exist."
            )
                return nothing
            end

            rethrow()
        end

        append!(events, convert.(LogEvent, response["events"]))

        curr_token = next_token
        next_token = response["nextForwardToken"]
    end

    return events
end
