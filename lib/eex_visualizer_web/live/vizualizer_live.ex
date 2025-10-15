defmodule EexVisualizerWeb.Macros do
  defmacro return_env() do
    __CALLER__ |> Macro.escape()
  end
end

defmodule EexVisualizerWeb.VisualizerLive do
  use Phoenix.LiveView, layout: {__MODULE__, :live}
  use EexVisualizerWeb, :live_view
  import EexVisualizerWeb.CoreComponents

  require EexVisualizerWeb.Macros

  @number_tabs 2

  @states []
  @tag_handler "Phoenix.LiveView.HTMLEngine"
  @source "Hello {@name}"
  @engine "Phoenix.LiveView.TagEngine"
  @user_assigns %{name: "John"}
  @visible_state 0

  @impl true
  def mount(_params, _session, socket) do
    socket
    |> assign(:buffer, Agent.start_link(fn -> [] end, name: :collector))
    |> assign(:auto_compile, true)
    |> update_socket(@source, @engine, @tag_handler, @user_assigns)
    |> ok()
  end

  def update_socket(socket, source, engine, tag_handler, user_assigns) do
    case compile(source, engine, tag_handler) do
      {:ok, states} ->
        socket
        |> assign(
          source: source,
          tag_handler: tag_handler,
          states: states,
          visible_state: 0,
          engine: engine,
          user_assigns: user_assigns
        )
        |> clear_flash()

      {:error, e} ->
        socket
        |> put_flash(:info, e.description)
    end
  end

  def handle_event("change", %{"auto_compile" => "false"} = params, socket),
    do:
      socket
      |> assign(:auto_compile, false)
      |> noreply()

  def handle_event("change", params, socket),
    do: handle_event("compile", params, socket)

  @impl true
  def handle_event(
        "compile",
        %{
          "source" => %{
            "source" => source,
            "engine" => engine,
            "assigns" => user_assigns,
            "tag_handler" => tag_handler
          },
          "auto_compile" => auto_compile
        },
        socket
      ) do
    user_assigns = Code.eval_string(user_assigns) |> elem(0)
    IO.inspect(auto_compile)

    socket
    |> assign(:auto_compile, auto_compile === "true")
    |> update_socket(source, engine, tag_handler, user_assigns)
    |> noreply()
  end

  def compile(source, engine, tag_handler) do
    try do
      EexVisualizer.Compiler.compile(source,
        engine: e(engine),
        tag_handler: e(tag_handler),
        caller: EexVisualizerWeb.Macros.return_env(),
        source: source
      )

      states = Enum.reverse(Agent.get(:collector, & &1))

      {:ok, states}
    rescue
      e -> {:error, e}
    end
  end

  def handle_event("increment", _, socket) do
    socket |> assign(visible_state: socket.assigns.visible_state + 1) |> noreply()
  end

  def handle_event("decrement", _, socket) do
    socket |> assign(visible_state: socket.assigns.visible_state - 1) |> noreply()
  end

  defp noreply(socket), do: {:noreply, socket}
  defp ok(socket), do: {:ok, socket}

  defp set_active_tab(js \\ %JS{}, tab) do
    js
    |> JS.remove_class("tab-active", to: "a.tab-active")
    |> JS.add_class("tab-active", to: tab)
  end

  defp show_active_content(js \\ %JS{}, "#content_tab_" <> to_nr = to) do
    Enum.reduce(0..@number_tabs, js, fn
      ^to_nr, js -> js
      idx, js -> JS.hide(js, to: "#content_tab_" <> to_string(idx))
    end)
    |> JS.show(to: to)
  end

  defp e(engine), do: Module.concat([engine])

  defp r(engine, state) do
    ast =
      case state do
        {_, _, _} -> state
        _ -> e(engine).handle_body(state)
      end

    ast |> Macro.to_string() |> String.trim() |> Code.format_string!()
  rescue
    e -> Map.get(e, :description) || Map.get(e, :message)
  end

  defp eval(ast, assigns) do
    {value, _} = Code.eval_quoted(ast, assigns: assigns)

    cond do
      match?(%Phoenix.LiveView.Rendered{}, value) ->
        try do
          value
          |> Phoenix.HTML.Safe.to_iodata()
          |> IO.iodata_to_binary()
        rescue
          e in KeyError ->
            Exception.message(e) |> raw()
        end

      is_binary(value) ->
        raw(value)

      true ->
        value |> to_string() |> raw()
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="flex gap-8 m-8">
        <div class="flex-1">
          <.form class="flex flex-col" phx-change="change" phx-submit="compile">
            <div class="flex self-end join">
              <label class="join-item btn pt-3">
                    <.input
                      class="checkbox checkbox-sm"
                      label="Auto"
                      type="checkbox"
                      checked={@auto_compile}
                      name="auto_compile"
                    />
                  </label>
          

              <.button
                class={[!@auto_compile && "text-orange-600", "join-item btn"]}
                type="submit"
                disabled={@auto_compile}
              >
                Compile
              </.button>
            </div>
            <.input
              type="select"
              name="source[engine]"
              label="Engine"
              options={[
                "EEx.SmartEngine",
                "Phoenix.LiveView.TagEngine"
              ]}
              value={@engine}
            />

            <.input
              type="select"
              name="source[tag_handler]"
              label="Tag Handler"
              options={["Phoenix.LiveView.HTMLEngine", "Phoenix.HTML.Engine"]}
              value={@engine}
            />

            <.input
              label="Assigns"
              name="source[assigns]"
              value={inspect(@user_assigns)}
            />

            <.input
              type="textarea"
              name="source[source]"
              placeholder="Enter the source code"
              rows={30}
              value={@source}
            />
          </.form>
        </div>

        <div class="flex-2 flex flex-col">
          <%= if not Enum.empty?(@states) do %>
            <div class="flex tabs-box ">
              <ul class="flex-1 tabs" role="tablist">
                <li class="tab_option">
                  <a
                    id="tab1"
                    role="tab"
                    class="tab tab-active"
                    phx-click={set_active_tab("#tab1") |> show_active_content("#content_tab_1")}
                  >
                    Generated Code
                  </a>
                </li>
                <li class="tab_option">
                  <a
                    id="tab2"
                    role="tab"
                    class="tab"
                    phx-click={set_active_tab("#tab2") |> show_active_content("#content_tab_2")}
                  >
                    Generated HTML
                  </a>
                </li>
              </ul>

              <div>
                <div class="flex justify-between gap-4 text-sm items-center text-xs">
                  <button
                    class="btn"
                    disabled={@visible_state == 0}
                    phx-click="decrement"
                  >
                    Prev
                  </button>
                  <div class="bold">State: {@visible_state + 1} / {length(@states)}</div>
                  <div class="bold">Handler: {Enum.at(@states, @visible_state).name}</div>

                  <button
                    class="btn"
                    disabled={@visible_state == length(@states) - 1}
                    phx-click="increment"
                  >
                    Next
                  </button>
                </div>
              </div>
            </div>

            <div id="content" class="tab_body flex-1 grow shrink basis-0 border-1 flex">
              <pre
                id="content_tab_1"
                class="bg-gray-900 text-white text-sm p-4 rounded-b-sm
               overflow-y-auto grow shrink basis-0"
              >

              {r(@engine, Enum.at(@states, @visible_state).buffer)}
            </pre>

              <div
                id="content_tab_2"
                class="hidden bg-gray-900 text-white text-sm p-4 rounded-b-sm
                overflow-y-auto grow shrink basis-0"
              >
                {eval(List.last(@states).buffer, @user_assigns)}
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
