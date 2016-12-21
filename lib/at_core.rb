require 'discordrb'
require 'observer'
require 'httparty'
require 'rufus-scheduler'
require 'sqlite3'
require_relative 'config'

class Allthing
  include Observable

  attr_accessor :bot,
                :scheduler,
                :database

  def initialize
    config = Configuration.new('config.json')
    #Create bot
    @bot = Discordrb::Commands::CommandBot.new(
      token:            config.get('token'),
      application_id:   config.get('appid'),
      prefix:           '!'
    )
    @scheduler = Rufus::Scheduler.new
    @database = SQLite3::Database.new "activity.db"
    setup
  end

  def setup
    bot.ready do |event|
      servers.each do |key, server|
        activity_monitor(server)
      end
    end

    bot.command :pug do |event|
      pug
    end

    bot.command :top do |event|
      top(event.server)
    end

    bot.command :dkp do |event, mod, user|
      user.gsub(/[^0-9]/, "")
      user = user.to_i

      p mod, user
    end
  end

  def pug
    begin
      url = 'http://pugme.herokuapp.com/random'
      pug = HTTParty.get(url).parsed_response["pug"]
      HTTParty.get(pug)
    rescue SocketError
      retry
    end

    return pug
  end

  def servers
    bot.servers
  end

  def channels(server)
    server.channels
  end

  def voice_users(server)
    afk_channel = server.afk_channel
    voice_users = []
    channels(server).each do |channel|
      if channel.type == "voice" && channel != afk_channel
        channel.users.each do |user|
          if user.mute == false &&
             user.deaf  == false &&
             user.self_mute == false &&
             user.self_deaf == false

            voice_users << user
          end
        end
      end
    end
    return voice_users
  end

  def activity_monitor(server)
    scheduler.every '1m' do
      voice_users(server).each do |user|
        update_activity(user, server.id, 1)
      end
    end
  end

  def update_activity(user, serverid, time_mod)
    p user.id, serverid

    begin
      database.execute "
        INSERT OR REPLACE INTO users (id, userid, serverid, time)
          VALUES (COALESCE((SELECT id FROM users WHERE userid=#{user.id} AND serverid=#{serverid}), NULL),
                  #{user.id},
                  #{serverid},
                  COALESCE((SELECT time FROM users WHERE userid=#{user.id}),'0') + #{time_mod}
          );"
    rescue Exception => e
      p e
    end
  end

  def mod_dkp(userid, dkp_mod)
    database.execute "
      INSERT OR REPLACE INTO dkp (id, dkp)
        VALUES (#{userid},
                COALESCE((SELECT dkp FROM dkp WHERE id=#{userid}), '0') + #{dkp_mod}
        );"
  end

  def top(server)
    output = []
    top_users = database.execute "SELECT * FROM users WHERE serverid = #{server.id} ORDER BY time DESC LIMIT 10"
    top_users.each do |user|
      id = user[1]
      minutes = user[3]
      name = server.member(id).name
      output << "#{name} - #{time(minutes)}"
    end

    return output.join("\n")
  end

  def time(minutes)
    hours   = minutes / 60
    minutes = minutes % 60
    out = ""

    if hours > 0
      out += "#{hours}h "
    end

    return out += "#{minutes}m"
  end
end
