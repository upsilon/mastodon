# frozen_string_literal: true

class Pubsubhubbub::ConfirmationWorker
  include Sidekiq::Worker
  include RoutingHelper

  sidekiq_options queue: 'push', retry: false

  def perform(subscription_id, mode, secret = nil, lease_seconds = nil)
    subscription = Subscription.find(subscription_id)
    challenge    = SecureRandom.hex

    subscription.secret        = secret
    subscription.lease_seconds = lease_seconds
    subscription.confirmed     = true

    topic = account_url(subscription.account, format: :atom)
    topic = topic.sub('丼.', 'xn--uiq.')

    response = HTTP.headers(user_agent: 'Mastodon/PubSubHubbub')
                   .timeout(:per_operation, write: 20, connect: 20, read: 50)
                   .get(subscription.callback_url, params: {
                          'hub.topic' => topic,
                          'hub.mode'          => mode,
                          'hub.challenge'     => challenge,
                          'hub.lease_seconds' => subscription.lease_seconds,
                        })

    body = response.body.to_s

    Rails.logger.debug "Confirming PuSH subscription for #{subscription.callback_url} with challenge #{challenge}: #{body}"

    if mode == 'subscribe' && body == challenge
      subscription.save!
    elsif (mode == 'unsubscribe' && body == challenge) || !subscription.confirmed?
      subscription.destroy!
    end
  end
end
