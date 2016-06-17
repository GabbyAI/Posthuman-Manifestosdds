require 'twitter_ebooks'
require 'rufus-scheduler'

# Information about a particular Twitter user we know
class UserInfo
  attr_reader :username

  # @return [Integer] how many times we can pester this user unprompted
  attr_accessor :pesters_left

  # @param username [String]
  def initialize(username)
    @username = username
    @pesters_left = 1
  end
end

require 'dotenv'  
Dotenv.load(".env")

require 'open-uri'

NUMBER_BOTS = ENV['EBOOKS_NUMBER_BOTS']
CONSUMER_KEY = ENV['EBOOKS_CONSUMER_KEY']  
CONSUMER_SECRET = ENV['EBOOKS_CONSUMER_SECRET']  
ACCOUNTS=Hash.new
i = 1
while i <= NUMBER_BOTS.to_i do
	ACCOUNTS[i]={:admin => ENV['EBOOKS_ADMIN_USERNAME_'+i.to_s], :username => ENV['EBOOKS_USERNAME_'+i.to_s], :original => ENV['EBOOKS_ORIGINAL_'+i.to_s], :oauth_token => ENV['EBOOKS_OAUTH_TOKEN_'+i.to_s], :oauth_token_secret => ENV['EBOOKS_OAUTH_TOKEN_SECRET_'+i.to_s], :blacklist =>ENV['EBOOKS_BLACKLIST_'+i.to_s]}
	i+=1
end

class CloneBot < Ebooks::Bot
 attr_accessor :original, :model, :model_path, :auth_name, :archive_path, :archive
 attr_accessor :followers, :following
  attr_accessor :account, :admin

  def initialize(account)
	  @account = account
	  super account[:username]
end

  def configure
    # Configuration for all CloneBots
    self.consumer_key = CONSUMER_KEY
    self.consumer_secret = CONSUMER_SECRET
    self.access_token = account[:oauth_token]
    self.access_token_secret = account[:oauth_token_secret]
    self.original = account[:original]

    self.original = account[:original]
    self.admin = account[:admin]

    @userinfo = {}
    
    load_model!
  end

  def top100; @top100 ||= model.keywords.take(100); end
  def top20;  @top20  ||= model.keywords.take(20); end

  def delay(&b)
    sleep (1..4).to_a.sample
    b.call
  end

  def on_startup
    scheduler.cron '0 0 * * *' do
	  # Be willing to bother people again tomorrow
	  @userinfo.each do |key,user|
        user.pesters_left = 1 if user.pesters_left == 0
	  end
    end
    scheduler.every '1m' do
      roll = rand
      chance = 80.0 / 100 / 120 # (80 % in 2 hours)
      if roll <= chance
        tweet(model.make_statement)
      end
    end
  end

  def on_message(dm)
      from_owner = dm.sender.screen_name.downcase == @original.downcase
      log "[DM from owner? #{from_owner}]"
    if from_owner
      action = dm.text.split.first.downcase
      strip_re = Regexp.new("^#{action}\s*", "i")
      payload = dm.text.sub(strip_re, "")
    case action
    when "tweet"
      tweet model.make_response(payload, 140)
    when "follow", "unfollow", "block"
      payload = parse_array(payload.gsub("@", ''), / *[,; ]+ */) # Strip @s and make array
      send(action.to_sym, payload)
    when "mention" 
      pre = payload + " "
      limit = 140 - pre.size
      message = "#{pre}#{model.make_statement(limit)}"
      tweet message
    when "breakbitch"
      tweet payload
    else
      log "Don't have behavior for action: #{action}"
      reply(dm, model.make_response(dm.text))
    end
     else
      delay do
       reply(dm, model.make_response(dm.text))
      end
    end
  end

  def on_mention(tweet)
    # Become more inclined to pester a user when they talk to us
    userinfo(tweet.user.screen_name).pesters_left += 1

    delay do
      reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
    end
  end

  def on_timeline(tweet)
    return if tweet.retweeted_status?
    return unless can_pester?(tweet.user.screen_name)

    tokens = Ebooks::NLP.tokenize(tweet.text)

    interesting = tokens.find { |t| top100.include?(t.downcase) }
    very_interesting = tokens.find_all { |t| top20.include?(t.downcase) }.length > 2

    delay do
      if very_interesting
        if rand < 0.01
          userinfo(tweet.user.screen_name).pesters_left -= 1
          reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
        end
      elsif interesting
        if rand < 0.001
          userinfo(tweet.user.screen_name).pesters_left -= 1
          reply(tweet, model.make_response(meta(tweet).mentionless, meta(tweet).limit))
        end
      end
    end
  end
 
  def userinfo(username)
    @userinfo[username] ||= UserInfo.new(username)
  end

  def can_pester?(username)
    userinfo(username).pesters_left > 0
  end
  
  private
  def load_model!
    return if @model
    @model_path ||= "model/GabbyNill.model"
    log "Loading model #{model_path}"
    @model = Ebooks::Model.load(model_path)
  end
end

  #TRANSHUMANISM WILL WIN
ACCOUNTS.each do |key, account|
	CloneBot.new(account)
end