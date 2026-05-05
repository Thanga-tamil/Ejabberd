-- ============================================================
-- MySQL Index Optimization Script
-- Source: Hike - MySQL Indexing Suggestions
-- ============================================================


-- ============================================================
-- TABLE: chat_recent
-- ============================================================

ALTER TABLE `chat_recent`
  -- DROP 8 redundant indexes
  DROP INDEX `chat_type`,
  DROP INDEX `to_user`,
  DROP INDEX `created_at`,
  DROP INDEX `idx_fromuser_status`,
  DROP INDEX `idx_status`,
  DROP INDEX `idx_recall`,
  DROP INDEX `idx_achive_status`,
  DROP INDEX `idx_from_user_msg_id`,
  -- ADD 5 new optimized indexes
  ADD INDEX `idx_to_user_message_time`    (to_user, message_time DESC),
  ADD INDEX `idx_to_user_created_at`      (to_user, created_at),
  ADD INDEX `idx_to_user_archive_status`  (to_user, archive_status),
  ADD INDEX `idx_to_user_chat_type`       (to_user, chat_type),
  ADD INDEX `idx_from_user_chat_type`     (from_user, chat_type);


-- ============================================================
-- TABLE: message_status
-- ============================================================

ALTER TABLE `message_status`
  -- DROP 7 redundant indexes
  DROP INDEX `message_status_msg_id`,
  DROP INDEX `from_user_to_user`,
  DROP INDEX `to_user`,
  DROP INDEX `faviroute_user`,
  DROP INDEX `message_notification`,
  DROP INDEX `blocked`,
  DROP INDEX `delete_status_change`,
  -- ADD 3 new optimized indexes
  ADD INDEX `idx_group_msg_time`            (from_user, message_time DESC),
  ADD INDEX `idx_to_user_status_created_at` (to_user, status, created_at),
  ADD INDEX `idx_group_notification`        (from_user, from_notification);


-- ============================================================
-- TABLE: spool
-- ============================================================

ALTER TABLE `spool`
  -- DROP 4 redundant indexes
  DROP INDEX `device_filter`,
  DROP INDEX `idx_cht_type`,
  DROP INDEX `i_spool_sh_username`,
  DROP INDEX `i_spool_user_device_msg_seq`,
  -- ADD 4 new optimized indexes
  ADD INDEX `idx_username_device_id_seq`   (`username`, `device_id`, `seq`),
  ADD INDEX `idx_spool_user_status_ctype`  (`username`, `status`, `chat_type`),
  ADD INDEX `idx_spool_to_user_username`   (`to_user`, `username`),
  ADD INDEX `idx_user_msg_id_device_id`    (`username`, `message_id`, `device_id`);


-- ============================================================
-- TABLE: rosterusers (DEV DATABASE)
-- ============================================================

ALTER TABLE `rosterusers`
  DROP INDEX `idx_roster_username_jid`,
  DROP INDEX `idx_roster_username`,
  DROP INDEX `idx_roster_jid_username`;

ALTER TABLE `rosterusers`
  ADD INDEX `i_rosteru_sh_jid`  (server_host, jid),
  ADD INDEX `idx_username`      (username),
  ADD INDEX `idx_user_jid`      (username, jid),
  ADD INDEX `idx_jid`           (jid);


-- ============================================================
-- TABLE: rosterusers (STAGING DATABASE)
-- Note: No drops needed — only additions required for staging
-- ============================================================

ALTER TABLE `rosterusers`
  ADD INDEX `idx_username`  (username),
  ADD INDEX `idx_user_jid`  (username, jid),
  ADD INDEX `idx_jid`       (jid);


-- ============================================================
-- TABLE: users_contacts
-- ============================================================

ALTER TABLE `users_contacts`
  ADD INDEX `idx_mobile_no` (mobile_number);


-- ============================================================
-- TABLE: chat_access_tokens
-- ============================================================

ALTER TABLE `chat_access_tokens`
  DROP INDEX `idx_chat_access_tokens_username`,
  ADD  INDEX `idx_username_device_type` (username, device_type);


-- ============================================================
-- TABLE: chat_message_edit_history
-- No changes required — all queries are already covered by:
--   KEY idx_messageid (message_id)
--   KEY idx_edit_message_id (edit_message_id)
-- ============================================================