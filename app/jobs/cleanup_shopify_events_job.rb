# frozen_string_literal: true

class CleanupShopifyEventsJob < ApplicationJob
  queue_as :default

  BATCH_SIZE = 10_000

  def perform
    cutoff_date = 30.days.ago

    deleted_count = ShopifyEvent.where(created_at: ...cutoff_date)
                                .in_batches(of: BATCH_SIZE)
                                .delete_all

    Rails.logger.info(
      "[CleanupShopifyEventsJob] #{deleted_count} eventos anteriores a " \
      "#{cutoff_date.iso8601} foram apagados."
    )

    deleted_count
  end
end
