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

  def process_fields(field_names, fields, req, fun),
    do: process_fields(field_names, [], fields, req, fun)

  defp process_fields([], values, fields, _req, fun),
    do: fun.(Enum.reverse(values), fields)

  defp process_fields([field | field_names], values, fields, req, fun) do
    process_field(field, fields, req,
      fn value, new_fields ->
        process_fields(field_names, [value | values], new_fields, req, fun)
      end)
  end

end
