require "sucker_punch"
require "sinatra"
require "sinatra/json"
require "json"
require "rest-client"
require "securerandom"
require "mongoid"
require "bunny"

$connection = Bunny.new("amqp://guest:guest@rabbitmq-service:5672")
$connection.start
Mongoid.load!(File.join(File.dirname(__FILE__), "config", "mongoid.yml"))

$channel = $connection.create_channel
order_queue = $channel.queue("order_created", :durable => false)

order_queue.subscribe do |_delivery_info, _properties, body|
  data = body.split("+")
  authorize_payment(data[0], data[1].to_i)
end

set :bind, "0.0.0.0"
set :port, 9000

get "/healthcheck" do
  status 200
  body "OK"
end

get "/client" do
  Client.all.to_json
end

get "/client/:id" do
  client_id = params["id"]
  client = Client.find(order_id)
  json(client)
end

post "/client" do
  body = JSON.parse(request.body.read)
  # check if card exist
  client = Client.create(name: body["name"], card: body["card"], amount: body["amount"], currency: body["currency"])
  json(client)
end

def authorize_payment(card_number, price)
  client = Client.find_by(card: card_number)
  is_authorized = "failed"
  if price <= client.amount
    client.amount = client.amount - price
    client.save
    is_authorized = "success"
  end

  message = "#{card_number}+#{is_authorized}"
  $channel.default_exchange.publish(message, routing_key: "authorize_payment")
end

class Client
  include Mongoid::Document

  field :name, type: String
  field :card, type: String
  field :amount, type: Integer
  field :currency, type: String
end
