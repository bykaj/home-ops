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
OAUTH_SCOPE = ["openid", "profile", "email"]
# Accounts are keyed on Pocket ID's sub, which survives username and email changes
OAUTH_ATTRIBUTE_MAP = {
    "sub": (True, "uid"),
    "email": (False, "contact_email"),
    "name": (False, "name"),
}
# The desktop and mobile apps sign in through the system browser
CLIENT_SSO_VIA_LOCAL_BROWSER = True

# SMTP relay
DEFAULT_FROM_EMAIL = os.environ.get("SMTP_FROM", "")
EMAIL_HOST = "smtp.bykaj.io"
EMAIL_PORT = 25
EMAIL_USE_SSL = False
EMAIL_USE_TLS = False
SERVER_EMAIL = DEFAULT_FROM_EMAIL
