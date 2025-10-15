defmodule EexVisualizerWeb.ErrorJSONTest do
  use EexVisualizerWeb.ConnCase, async: true

  test "renders 404" do
    assert EexVisualizerWeb.ErrorJSON.render("404.json", %{}) == %{errors: %{detail: "Not Found"}}
  end

  test "renders 500" do
    assert EexVisualizerWeb.ErrorJSON.render("500.json", %{}) ==
             %{errors: %{detail: "Internal Server Error"}}
  end
end
