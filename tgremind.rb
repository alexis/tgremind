#!/usr/bin/env ruby

require 'yaml'
require 'bundler'
Bundler.require(:default)

DELAY = 60
API_TOKEN = ENV['API_TOKEN']
LOGGER = Logger.new(STDOUT, level: ENV['DEBUG'] ? :debug : :info)
SILENT_START = ENV['SILENT_START']

fail('Error: API_TOKEN environment variable required') if API_TOKEN.blank?
String.disable_colorization(true) unless STDOUT.isatty

Time.zone = ENV['TZ'] || 'UTC'
Chronic.time_class = Time.zone

def api_endpoint(action)
  "https://api.telegram.org/bot#{API_TOKEN}/#{action}"
end

def send_notifications(msg, ids: nil)
  LOGGER.debug "Message to send: #{msg.bold}"
  return if ENV['DRYRUN']

  ids ||= get_chats
  ids.each do |chat_id|
    LOGGER.info "Sending message to #{chat_id.to_s.green}: #{msg.bold}"
    Typhoeus.post(api_endpoint(:sendMessage), body: {
      chat_id: chat_id,
      parse_mode: 'markdown',
      text: msg
    })
  end
end

def remember_chats(current_chats)
  @chats = [*@chats, *current_chats].uniq
end

def get_chats
  json = JSON.parse(Typhoeus.get(api_endpoint(:getUpdates)).body)
  discovered_chats =
    json['result'].map{ |x| x.values.map{ |y| y.is_a?(Hash) ? y.dig('chat', 'id') : nil} }.flatten.uniq.compact
  remember_chats(discovered_chats)
end

def each_parsed_reminder
  get_chats.each do |chat_id|
    res = JSON.parse(Typhoeus.get(api_endpoint(:getChat), params: {chat_id: chat_id}).body)
    descr = res.dig('result', 'description')
    return unless descr

    descr.scan(%r{^(REMINDER: *(.*) // (.*))}) do |match|
      whole_string, datetime_str, descr = *match
      yield chat_id, whole_string, Chronic.parse(datetime_str, now: Time.current - 1.day), descr[/^[^@]*/].squish
    end
  end
end

def shut_down
  Thread.new {
    send_notifications("Reminders is OFF")
    exit
  }
end
Signal.trap("INT")  { shut_down }
Signal.trap("TERM") { shut_down }

send_notifications("Reminders is ON") unless SILENT_START

last_time = Time.current
while true
  this_time = Time.current

  each_parsed_reminder do |chat_id, msg, event_time, event_name|
    hours_until = []
    [event_time - 15.minutes, event_time.beginning_of_day - 4.hours].each do |remind_at|
      send_notifications(msg, ids: [chat_id]) if last_time < remind_at and this_time > remind_at
      hours_until << '%.2fh' % ((remind_at - this_time) / 3600)
    end
    LOGGER.info "Remind #{chat_id.to_s.green} about #{event_name.bold} in: #{ hours_until.join(', ') }"
  end

  last_time = this_time
  sleep DELAY
end
