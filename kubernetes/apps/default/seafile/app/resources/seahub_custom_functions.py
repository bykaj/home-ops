# Imported by Seahub's OAuth login (seahub/oauth/views.py): maps the role value,
# here Pocket ID's groups claim (see OAUTH_ATTRIBUTE_MAP), to a Seafile role from
# ENABLED_ROLE_PERMISSIONS in local_settings.py. The container command links it
# next to the seahub package. Highest group first; users in none get "default".
ROLES = ("admins", "family", "friends")


def custom_get_user_role(groups):
    if isinstance(groups, str):
        groups = [groups]
    for role in ROLES:
        if role in groups:
            return role
    return "default"
