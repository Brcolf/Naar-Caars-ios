# Webhook Request Body - Parameter Format

If the webhook form shows **"Parameter Name"** and **"Parameter Value"** fields, here's how to set it up:

## Option 1: Add Multiple Parameters (Recommended)

Click **"+ Add Parameter"** (or similar button) **4 times** to add 4 parameter pairs:

### Parameter 1:
- **Parameter Name**: `id`
- **Parameter Value**: `{{NEW.id}}`

### Parameter 2:
- **Parameter Name**: `conversation_id`
- **Parameter Value**: `{{NEW.conversation_id}}`

### Parameter 3:
- **Parameter Name**: `from_id`
- **Parameter Value**: `{{NEW.from_id}}`

### Parameter 4:
- **Parameter Name**: `text`
- **Parameter Value**: `{{NEW.text}}`

---

## Option 2: Use JSON Template (If Available)

If there's a toggle or option to switch to **"JSON"** or **"Custom"** mode:
1. Look for a dropdown or toggle that says "JSON" or "Raw" or "Custom"
2. Switch to that mode
3. Then paste the full JSON in a single text area:

```json
{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}
```

---

## Step-by-Step with Parameters

1. Click **"+ Add Parameter"** (or **"+ Add Field"** or similar button)

2. **First Parameter**:
   - **Parameter Name**: Type `id`
   - **Parameter Value**: Type `{{NEW.id}}`
   - (Keep the `{{` and `}}` exactly as shown)

3. Click **"+ Add Parameter"** again

4. **Second Parameter**:
   - **Parameter Name**: Type `conversation_id`
   - **Parameter Value**: Type `{{NEW.conversation_id}}`

5. Click **"+ Add Parameter"** again

6. **Third Parameter**:
   - **Parameter Name**: Type `from_id`
   - **Parameter Value**: Type `{{NEW.from_id}}`

7. Click **"+ Add Parameter"** again

8. **Fourth Parameter**:
   - **Parameter Name**: Type `text`
   - **Parameter Value**: Type `{{NEW.text}}`

---

## Visual Guide

```
┌─────────────────────────────────────────┐
│ Request Body Template                   │
├─────────────────────────────────────────┤
│ Parameter Name    Parameter Value       │
├─────────────────────────────────────────┤
│ id               {{NEW.id}}             │
│ conversation_id  {{NEW.conversation_id}}│
│ from_id          {{NEW.from_id}}        │
│ text             {{NEW.text}}           │
├─────────────────────────────────────────┤
│ [+ Add Parameter]                       │
└─────────────────────────────────────────┘
```

---

## Important Notes

- Keep the `{{` and `}}` exactly as shown in the Parameter Value fields
- Don't include quotes around the values (just `{{NEW.id}}`, not `"{{NEW.id}}"`)
- Make sure parameter names are exactly as shown (lowercase, with underscores)

---

## If You See "Raw" or "JSON" Option

Some webhook UIs have a toggle to switch between "Form" and "Raw JSON" modes:

1. Look for a **"Raw"**, **"JSON"**, or **"Custom"** toggle/button
2. Switch to that mode
3. You'll see a single text area where you can paste the full JSON:

```json
{
  "id": "{{NEW.id}}",
  "conversation_id": "{{NEW.conversation_id}}",
  "from_id": "{{NEW.from_id}}",
  "text": "{{NEW.text}}"
}
```

This is easier if available!


