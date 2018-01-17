defmodule SSETestServer.HandlerUtils do

  def success(req), do: :cowboy_req.reply(204, req)

  def bad_request(req, msg), do: :cowboy_req.reply(400, %{}, msg, req)

  def missing_field(req, field),
    do: bad_request(req, "Missing field: #{field}")

  def process_field(field, fields, req, fun) do
    case Map.pop(fields, field) do
      {nil, _} -> missing_field(req, field)
      {value, remaining_fields} -> fun.(value, remaining_fields)
    end
  end

end
