# Seahub imports seahub/local_settings.py before conf/seahub_settings.py, which
# the first start generates on the PVC. The container command links this file
# into place; secrets come from the environment.
import os

# Pocket ID
ENABLE_OAUTH = True
OAUTH_ACTIVATE_USER_AFTER_CREATION = True
OAUTH_CREATE_UNKNOWN_USER = True
OAUTH_CLIENT_ID = os.environ.get("OAUTH_CLIENT_ID", "")
OAUTH_CLIENT_SECRET = os.environ.get("OAUTH_CLIENT_SECRET", "")
OAUTH_PROVIDER = "cyrannus.id"
OAUTH_AUTHORIZATION_URL = "https://cyrannus.id/authorize"
OAUTH_TOKEN_URL = "https://cyrannus.id/api/oidc/token"
OAUTH_USER_INFO_URL = "https://cyrannus.id/api/oidc/userinfo"
OAUTH_REDIRECT_URL = "https://%s/oauth/callback/" % os.environ.get("SEAFILE_SERVER_HOSTNAME", "")
# Pocket ID only sends the groups claim for the groups scope
OAUTH_SCOPE = ["openid", "profile", "email", "groups"]
# Accounts are keyed on Pocket ID's sub, which survives username and email changes
OAUTH_ATTRIBUTE_MAP = {
    "sub": (True, "uid"),
    "email": (False, "contact_email"),
    "name": (False, "name"),
    # Becomes the user's role on every login, see seahub_custom_functions.py
    "groups": (False, "role"),
}
# The desktop and mobile apps sign in through the system browser
CLIENT_SSO_VIA_LOCAL_BROWSER = True

# Roles from the Pocket ID groups; everything not set here comes from Seahub's
# built-in "default" role. 100 AI credits = USD 1 at the prices in LLM_MODELS
ENABLED_ROLE_PERMISSIONS = {
    # Seahub's own default is unlimited AI and no quota; it applies to users in
    # none of the groups, the local admin and accounts until their next login
    "default": {
        "monthly_ai_credit_per_user": 0,
        "role_quota": "1g",
    },
    "admins": {
        "monthly_ai_credit_per_user": -1,
        "role_quota": "100g",
    },
    "family": {
        "monthly_ai_credit_per_user": 500,
        "role_quota": "100g",
    },
    "friends": {
        "monthly_ai_credit_per_user": 200,
        "role_quota": "50g",
    },
}

# SMTP relay
DEFAULT_FROM_EMAIL = os.environ.get("SMTP_FROM", "")
EMAIL_HOST = "smtp.bykaj.io"
EMAIL_PORT = 25
EMAIL_USE_SSL = False
EMAIL_USE_TLS = False
SERVER_EMAIL = DEFAULT_FROM_EMAIL
