using Compat: AbstractDict

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
