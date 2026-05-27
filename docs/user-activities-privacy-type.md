# User activities: update `privacy_type` (IQ)

Updates the MySQL **`chat_users.privacy_type`** column for the **currently authenticated user** (JID bare localpart on the inbound IQ `from`). The server does **not** allow changing another account’s row via this IQ.

---

## Database

| Column         | Table        | Allowed values                         | Nullable |
|----------------|--------------|----------------------------------------|----------|
| `privacy_type` | `chat_users` | `contact`, `include`, `exclude` (enum) | Yes      |

Setting an **empty** `privacy_type` on the request maps to **`NULL`** in the database (clears the setting).

---

## XMPP: IQ set

- **Handler module:** `fly_mod_user_activities`
- **IQ type:** `set`
- **Codec / namespace:** `jabber:iq:user_activities` (see `xmpp_codec.spec` → `user_activities` → `privacy_type` attribute on `<query>`)

### Request semantics

1. **Operation name (status)**

   The first decoded child `#user_activities{ status = RequestType }` must use:

   ```text
   RequestType = <<"update_privacy_type">>
   ```

   Same pattern as other user-activities operations (e.g. `update_archive_chat`).

2. **Payload (query)**

   The `<query xmlns='jabber:iq:user_activities'>` element must include attribute:

   | Attribute       | Required | Meaning |
   |-----------------|----------|---------|
   | `privacy_type` | No*      | `contact` \| `include` \| `exclude` \| **empty** (clear → `NULL`) |

   \* Omitting vs empty string depends on client; **`fxml:get_path_s`** treats missing attrs as **`<<>>`**, which clears the column.

---

## Value rules

| Client sends (`privacy_type` attr)       | Stored in DB   |
|------------------------------------------|----------------|
| `contact` (any case, e.g. `Contact`)     | `contact`      |
| `include`                                | `include`      |
| `exclude`                                | `exclude`      |
| `""` / omitted (→ empty binary)           | `NULL`         |
| Anything else                             | IQ error below |

Normalization uses **`string:lowercase/1`** before SQL.

---

## Response (IQ result)

Wire format is defined in **`xmpp_codec.spec`** as separate elements (module **`user_activities`**, xmlns **`jabber:iq:user_activities`**):

| Element | When | Attributes / CDATA |
|---------|------|----------------------|
| **`privacy_setting`** | Success | `privacy_type` — echoed value (lowercased), or empty if cleared |
| **`privacy_type_error`** | Invalid enum | `code` = `invalid_privacy_type`, `message` = full English error text |

Both responses also set **`result_type`** (CDATA on the parent `query`) for the same strings as below.

### Success

- **`result_type` (CDATA):** `Updated successfully`
- **`sub_els`:** one **`privacy_setting`** child, e.g.  
  `<privacy_setting xmlns='jabber:iq:user_activities' privacy_type='include'/>`

### Invalid `privacy_type` value

- **`result_type` (CDATA):** `Invalid privacy_type; allowed: contact, include, exclude`
- **`sub_els`:** one **`privacy_type_error`** child, e.g.  
  `<privacy_type_error xmlns='jabber:iq:user_activities' code='invalid_privacy_type' message='Invalid privacy_type; allowed: contact, include, exclude'/>`

---

## Related: `privacy_setting` **handler** (different feature)

The existing **`privacy_setting/4`** function handles **seen_receipt / hide_profile** signalling. That is unrelated to the **`privacy_setting`** **XML element** returned by **`update_privacy_type`** (same local name, different use).

---

## Example stanza

```xml
<iq type="set"
    id="update-privacy-1"
    to="your.host.example"
    xmlns="jabber:client">
  <!-- Status must match IQ decoder: first user_activities sub-element -->
  <user_activities xmlns="jabber:iq:user_activities" status="update_privacy_type"/>
  <query xmlns="jabber:iq:user_activities" privacy_type="include"/>
</iq>
```

Adjust **`xmlns` on `<user_activities>`** if your codec uses the same IQ namespace as existing user-activities stanzas in your mobile/web clients.

---

## Erlang references

| Piece                    | Location |
|--------------------------|----------|
| IQ routing / `case`      | `fly_mod_user_activities:process_iq_set/4` → `<<"update_privacy_type">>` |
| IQ handler               | `fly_mod_user_activities:update_privacy_type/4` |
| SQL + validation         | `fly_mod_utils:set_privacy_type/2`, `normalize_chat_privacy_type/1` |
| Types (`-spec` / export) | `fly_mod_utils`, `fly_mod_user_activities` |
| Codec field              | `xmpp_codec.spec` → `-xml(user_activities, ...)`, attrs + `'$privacy_type'` |
| Result child elements    | `-xml(privacy_setting, ...)`, `-xml(privacy_type_error, ...)` |

After changing **`xmpp_codec.spec`**, rebuild the project (copy spec into **`deps/xmpp/specs/`** per `Dockerfile`) so generated codecs include **`privacy_type`** on `#user_activities{}` and the **`#privacy_setting{}` / `#privacy_type_error{}`** records.
