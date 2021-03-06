defmodule CadetWeb.AuthController do
  use CadetWeb, :controller
  use PhoenixSwagger

  alias Cadet.Accounts
  alias Cadet.Accounts.User
  alias Cadet.Auth.{Guardian, Provider}

  @doc """
  Receives a /login request with valid attributes (`Login form`).

  If the user is already registered in our database, simply return `Tokens`. If
  the user has not been registered before, register the user, then return the
  `Tokens`.
  """
  def create(
        conn,
        params = %{
          "code" => code,
          "provider" => provider
        }
      ) do
    client_id = Map.get(params, "client_id")
    redirect_uri = Map.get(params, "redirect_uri")

    with {:authorise, {:ok, %{token: token, username: username}}} <-
           {:authorise, Provider.authorise(provider, code, client_id, redirect_uri)},
         {:signin, {:ok, user}} <- {:signin, Accounts.sign_in(username, token, provider)} do
      render(conn, "token.json", generate_tokens(user))
    else
      {:authorise, {:error, :upstream, reason}} ->
        conn
        |> put_status(:bad_request)
        |> text("Unable to retrieve token from ADFS: #{reason}")

      {:authorise, {:error, :invalid_credentials, reason}} ->
        conn
        |> put_status(:bad_request)
        |> text("Unable to validate token: #{reason}")

      {:authorise, {:error, _, reason}} ->
        conn
        |> put_status(:internal_server_error)
        |> text("Unknown error: #{reason}")

      {:signin, {:error, status, reason}} ->
        # reason can be :bad_request or :internal_server_error
        conn
        |> put_status(status)
        |> text("Unable to retrieve user: #{reason}")
    end
  end

  @doc """
  Receives a /login request with invalid attributes.
  """
  def create(conn, _params) do
    send_resp(conn, :bad_request, "Missing parameter")
  end

  @doc """
  Receives a /refresh request with valid attribute.

  Exchanges the refresh_token with a new access_token.
  """
  def refresh(conn, %{"refresh_token" => refresh_token}) do
    # TODO: Refactor to use refresh after guardian_db > v1.1.0 is released.
    case Guardian.resource_from_token(refresh_token) do
      {:ok, user, %{"typ" => "refresh"}} ->
        render(conn, "token.json", generate_tokens(user))

      _ ->
        send_resp(conn, :unauthorized, "Invalid Token")
    end
  end

  @doc """
  Receives a /refresh request with invalid attributes.
  """
  def refresh(conn, _params) do
    send_resp(conn, :bad_request, "Missing parameter")
  end

  @doc """
  Receives a /logout request with valid attribute.
  """
  def logout(conn, %{"refresh_token" => refresh_token}) do
    case Guardian.decode_and_verify(refresh_token) do
      {:ok, _} ->
        Guardian.revoke(refresh_token)
        text(conn, "OK")

      {:error, _} ->
        send_resp(conn, :unauthorized, "Invalid Token")
    end
  end

  @doc """
  Receives a /logout request with invalid attributes.
  """
  def logout(conn, _params) do
    send_resp(conn, :bad_request, "Missing parameter")
  end

  @spec generate_tokens(%User{}) :: %{access_token: String.t(), refresh_token: String.t()}
  defp generate_tokens(user) do
    {:ok, access_token, _} =
      Guardian.encode_and_sign(user, %{}, token_type: "access", ttl: {1, :hour})

    {:ok, refresh_token, _} =
      Guardian.encode_and_sign(user, %{}, token_type: "refresh", ttl: {1, :week})

    %{access_token: access_token, refresh_token: refresh_token}
  end

  swagger_path :create do
    post("/auth")

    summary("Obtain access and refresh tokens to authenticate user.")

    description(
      "Get a set of access and refresh tokens, using the authentication code " <>
        "from the OAuth2 provider. When accessing resources, pass the access " <>
        "token in the Authorization HTTP header using the Bearer schema: " <>
        "`Authorization: Bearer <token>`."
    )

    consumes("application/json")
    produces("application/json")

    parameters do
      code(:body, :string, "OAuth2 code", required: true)
      provider(:body, :string, "OAuth2 provider ID", required: true)
      client_id(:body, :string, "OAuth2 client ID", required: false)
      redirect_uri(:body, :string, "OAuth2 redirect URI", required: false)
    end

    response(200, "OK", Schema.ref(:Tokens))
    response(400, "Missing or invalid parameters or credentials, or upstream error")
    response(500, "Internal server error")
  end

  swagger_path :refresh do
    post("/auth/refresh")
    summary("Obtain a new access token using a refresh token")
    consumes("application/json")
    produces("application/json")

    parameters do
      refresh_token(
        :body,
        Schema.ref(:RefreshToken),
        "refresh token obtained from /auth",
        required: true
      )
    end

    response(200, "OK", Schema.ref(:Tokens))
    response(400, "Missing parameter(s)")
    response(401, "Invalid refresh token")
  end

  swagger_path :logout do
    post("/auth/logout")
    summary("Logout and invalidate the tokens")
    consumes("application/json")

    parameters do
      tokens(:body, Schema.ref(:RefreshToken), "refresh token to be invalidated", required: true)
    end

    response(200, "OK")
    response(400, "Missing parameter(s)")
    response(401, "Invalid token")
  end

  def swagger_definitions do
    %{
      Tokens:
        swagger_schema do
          title("Tokens")

          properties do
            access_token(:string, "Access token with TTL of 1 hour")
            refresh_token(:string, "Refresh token with TTL of 1 week")
          end
        end,
      RefreshToken:
        swagger_schema do
          title("Refresh Token")

          properties do
            refresh_token(:string, "Refresh token", required: true)
          end
        end
    }
  end
end
