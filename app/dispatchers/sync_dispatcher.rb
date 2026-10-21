class SyncDispatcher < BaseDispatcher
  def dispatch(event_name, timestamp, data)
    event_object = Events::Base.new(event_name, timestamp, data)
    publish(event_object.method_name, event_object)
  end

  def listeners
    [ActionCableListener.instance, AgentBotListener.instance,
     Arroyo::CommercialListener.instance, # ARROYO: actor/origen comercial antes de los procesos asíncronos
     Arroyo::PostSaleListener.instance] # ARROYO: fecha y vendedor al registrar vendido
  end
end
