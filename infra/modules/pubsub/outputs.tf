output "topic_ids" {
  description = "Topic name → full topic id."
  value       = { for k, t in google_pubsub_topic.t : k => t.id }
}

output "dlq_topic_ids" {
  description = "Topic name → dead-letter topic id."
  value       = { for k, t in google_pubsub_topic.dlq : k => t.id }
}

output "subscription_names" {
  description = "Topic name → worker subscription name."
  value       = { for k, s in google_pubsub_subscription.main : k => s.name }
}
