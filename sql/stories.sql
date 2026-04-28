CREATE TABLE stories (
    story_id bigint AUTO_INCREMENT PRIMARY KEY,
    username varchar(191) NOT NULL,
    media_url text NOT NULL,
    thumb_url text,
    caption text,
    story_type varchar(20) NOT NULL, -- image, video, text
    duration int DEFAULT 0,
    expiry_time timestamp NOT NULL,
    created_at timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX i_stories_username (username),
    INDEX i_stories_expiry (expiry_time)
) ENGINE=InnoDB CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
