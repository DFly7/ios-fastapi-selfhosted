import uvicorn

if __name__ == "__main__":
    host = "0.0.0.0"
    port = 8000

    display_host = "127.0.0.1" if host in ("0.0.0.0", "::") else host
    base_url = f"http://{display_host}:{port}"

    print("")
    print(f"API running at {base_url}")
    print(f"Swagger UI: {base_url}/docs")
    print(f"ReDoc:      {base_url}/redoc")
    print("")

    uvicorn.run(
        "app.main:app",
        host=host,
        port=port,
        reload=True,
    )
