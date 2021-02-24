struct BatchEnvironmentError <: Exception
    message::String
end
Base.showerror(io::IO, e::BatchEnvironmentError) = print(io, "BatchEnvironmentError: ", e.message)

struct BatchJobError <: Exception
    job_id::AbstractString
    message::String
end
Base.showerror(io::IO, e::BatchJobError) = print(io, "BatchJobError: $(e.job_id)", e.message)
