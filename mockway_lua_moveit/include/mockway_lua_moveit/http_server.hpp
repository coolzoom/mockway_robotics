#pragma once

#include <httplib.h>
#include <memory>
#include <atomic>
#include <thread>
#include <string>

class LuaMoveItNode;

/**
 * HttpServer
 *
 * 为前端 UI 提供以下 HTTP 接口：
 *   静态文件   GET  /              — 托管 share/mockway_lua_moveit/dist/
 *   Lua 执行   POST /api/lua       — 执行 Lua 脚本字符串
 *   关节状态   GET  /api/joints    — SSE 实时推送关节/位姿数据（100 ms 周期）
 *   配置读取   GET  /api/config    — 读取 system_config.json
 *   配置写入   POST /api/config    — 写入 system_config.json
 */
class HttpServer
{
public:
  explicit HttpServer(std::shared_ptr<LuaMoveItNode> node, int port = 8080);
  ~HttpServer();

  void start();
  void stop();

  bool is_running() const { return running_.load(); }

private:
  std::shared_ptr<LuaMoveItNode> node_;
  httplib::Server                svr_;
  std::thread                    thread_;
  std::atomic<bool>              running_{false};
  int                            port_;

  void        setup_routes();
  std::string web_root()    const;
  std::string config_path() const;
};
